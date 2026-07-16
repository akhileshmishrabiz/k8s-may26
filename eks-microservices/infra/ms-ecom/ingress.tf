# ALB ingress resources for ecommerce services.
# Namespace is created by namespace.tf in this module.
# Ingress is managed by Terraform (Helm ingress is disabled in argocd-app.tf).

locals {
  # Wildcard cert is *.app_subdomain.domain (e.g. *.devopsdozo.livingdevops.org).
  ingress_services = var.enable_ingress ? {
    for svc_key, svc_cfg in var.ingress_services :
    svc_key => {
      namespace         = var.namespace
      environment_label = var.environment_label
      svc_key           = svc_key
      host = coalesce(
        try(svc_cfg.host, null),
        "${coalesce(try(svc_cfg.host_prefix, null), svc_key == "frontend" ? var.subdomain : svc_key)}.${var.app_subdomain}.${var.domain_name}"
      )
      path             = try(svc_cfg.path, "/")
      path_type        = try(svc_cfg.path_type, "Prefix")
      service_name     = svc_cfg.service_name
      service_port     = svc_cfg.service_port
      healthcheck_path = try(svc_cfg.healthcheck_path, "/health")
    }
    if try(svc_cfg.enabled, true)
  } : {}
}

resource "kubernetes_ingress_v1" "service" {
  for_each = local.ingress_services

  metadata {
    name      = "${each.key}-ingress"
    namespace = each.value.namespace

    annotations = {
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
      "alb.ingress.kubernetes.io/certificate-arn"          = local.acm_cert_arn
      "alb.ingress.kubernetes.io/healthcheck-path"         = each.value.healthcheck_path
      "alb.ingress.kubernetes.io/healthcheck-protocol"     = "HTTP"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
      "alb.ingress.kubernetes.io/ssl-policy"               = "ELBSecurityPolicy-TLS-1-2-2017-01"
      "alb.ingress.kubernetes.io/tags"                     = "Environment=${each.value.environment_label},ManagedBy=Terraform,Name=${var.app_subdomain}-ingress"
      "alb.ingress.kubernetes.io/group.name"               = var.alb_group_name
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts = [each.value.host]
    }

    rule {
      host = each.value.host

      http {
        path {
          path      = each.value.path
          path_type = each.value.path_type

          backend {
            service {
              name = each.value.service_name
              port {
                number = each.value.service_port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.ecommerce]
}
