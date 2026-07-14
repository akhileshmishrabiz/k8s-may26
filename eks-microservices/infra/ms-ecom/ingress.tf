resource "kubernetes_ingress_v1" "ecommerce" {
  metadata {
    name      = var.ingress_name
    namespace = var.namespace

    annotations = {
      # Internet-facing ALB
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # Health check
      "alb.ingress.kubernetes.io/healthcheck-path" = "/health"

      # Listen on both HTTP and HTTPS
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"

      # Redirect HTTP → HTTPS
      "alb.ingress.kubernetes.io/ssl-redirect" = "443"

      # SSL policy
      "alb.ingress.kubernetes.io/ssl-policy" = "ELBSecurityPolicy-TLS-1-2-2017-01"

      # ACM certificate
      "alb.ingress.kubernetes.io/certificate-arn" = var.acm_cert_arn

      # HTTP 301 redirect action
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": {\"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"

      # Share the same ALB as ArgoCD
      "alb.ingress.kubernetes.io/group.name" = var.alb_group_name
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    # TLS block
    tls {
      hosts = [
        "${var.subdomain}.${var.domain_name}"
      ]
    }

    rule {
      host = "${var.subdomain}.${var.domain_name}"

      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = var.api_gateway_service_name
              port {
                number = var.service_port
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.frontend_service_name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}