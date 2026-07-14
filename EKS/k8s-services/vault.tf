# Explicit DNS for Vault UI/API. The argocd stack may also define *.livingdevops.org;
# this record guarantees vault.<domain> resolves even if the wildcard is missing or stale.

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ALB controller populates ingress.status asynchronously after create.
resource "time_sleep" "wait_for_vault_ingress" {
  depends_on      = [kubernetes_ingress_v1.vault]
  create_duration = "60s"
}

data "kubernetes_ingress_v1" "vault" {
  metadata {
    name      = kubernetes_ingress_v1.vault.metadata[0].name
    namespace = kubernetes_ingress_v1.vault.metadata[0].namespace
  }

  depends_on = [time_sleep.wait_for_vault_ingress]
}

resource "aws_route53_record" "vault" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "vault.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.kubernetes_ingress_v1.vault.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = var.aws_alb_zoneid
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.vault]
}


resource "kubernetes_namespace_v1" "vault" {
  metadata {
    name = "vault"
  }
}

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = kubernetes_namespace_v1.vault.metadata[0].name

  values = [yamlencode({
    global = {
      enabled = true
    }

    server = {
      enabled = true

      # Dev mode - auto-unsealed, in-memory storage. Lab use only.
      dev = {
        enabled      = true
        devRootToken = "root"
      }

      resources = {
        requests = {
          memory = "128Mi"
          cpu    = "100m"
        }
        limits = {
          memory = "256Mi"
          cpu    = "250m"
        }
      }

      # ClusterIP - ALB ingress handles external traffic
      service = {
        type = "ClusterIP"
      }

      extraEnvironmentVars = {
        VAULT_LOG_LEVEL = "info"
      }
    }

    ui = {
      enabled = true
    }

    # ESO handles secret sync; sidecar injector not needed
    injector = {
      enabled = false
    }
  })]
}

resource "kubernetes_ingress_v1" "vault" {
  metadata {
    name      = "vault-ui-ingress"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name

    annotations = {
      "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/v1/sys/health?standbyok=true&uninitcode=200"
      "alb.ingress.kubernetes.io/listen-ports"         = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"         = "443"
      "alb.ingress.kubernetes.io/ssl-policy"           = "ELBSecurityPolicy-TLS-1-2-2017-01"
      "alb.ingress.kubernetes.io/certificate-arn"      = aws_acm_certificate.microservices_cert.arn
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": {\"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/group.name"           = "k8sbatch-shared-alb"
    }
  }

  spec {
    ingress_class_name = "alb"

    tls {
      hosts = [
        "vault.${var.domain_name}"
      ]
    }

    rule {
      host = "vault.${var.domain_name}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "vault"
              port {
                number = 8200
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.vault]
}

