# backend secrets

resource "random_password" "backend_secret_key" {
  length           = 32
  special          = false
  override_special = "$#@!%^&*()_+-=[]{}|;:,.<>?abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
}

#create namespace
resource "kubernetes_namespace" "namespace" {
  metadata {
    annotations = {
      name = var.app_namepace
    }

    name = var.app_namepace
  }
}


# create secrets and configmaps for both apps

resource "kubernetes_config_map" "backend" {
  metadata {
    name = "backend-configmap"
    namespace = var.app_namepace
  }

  data = {
    FLASK_APP       = "run.py",
    FLASK_DEBUG     = "1",
    DB_HOST         = aws_db_instance.postgres.address,
    DB_PORT         = aws_db_instance.postgres.port,
    DB_NAME         = aws_db_instance.postgres.db_name,
    # CORS allowed origins
    ALLOWED_ORIGINS = "https://devopsdozo.livingdevops.org,http://devopsdozo.livingdevops.org"
  }

depends_on = [ kubernetes_namespace.namespace ]
}

resource "kubernetes_secret" "backend" {
  metadata {
    name = "backend-secrets"
    namespace = var.app_namepace
  }

  data = {
   DATABASE_URL = "postgresql://${aws_db_instance.postgres.username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}",
    SECRET_KEY   = random_password.backend_secret_key.result,
    DB_USERNAME  = aws_db_instance.postgres.username,
    DB_PASSWORD  = random_password.db_password.result
  }

  type = "opaque"
}

# menifest for frontend and  backend deployments and services via terraform


resource "kubernetes_config_map" "frontend" {
  metadata {
    name = "frontend-configmap"
    namespace = var.app_namepace
  }

  data = {
    # BACKEND_URL = "http://backend:8000"
    BACKEND_URL = "http://${kubernetes_service.backend.spec[0].cluster_ip}:${kubernetes_service.backend.spec[0].port[0].port}"
  }

depends_on = [ kubernetes_namespace.namespace ]
}





# ingress   

# Ingress with TLS/SSL Configuration

resource "kubernetes_ingress_v1" "app_ingress_tls" {
  metadata {
    name      = "${var.app_subdomain}-ingress"
    namespace = var.app_namepace
    annotations = {
      # ALB configuration
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # SSL/TLS configuration
      "alb.ingress.kubernetes.io/listen-ports"        = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"        = "443"
      "alb.ingress.kubernetes.io/certificate-arn"     = aws_acm_certificate.app.arn

      # Health check configuration
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/health"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"

      # Load balancer attributes
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"

      # Tags for the ALB
      "alb.ingress.kubernetes.io/tags" = "Environment=production,ManagedBy=Terraform,Name=${var.app_subdomain}-ingress"
    }
  }

  depends_on = [
    kubernetes_namespace.namespace,
    aws_acm_certificate_validation.app
  ]

  spec {
    ingress_class_name = "alb"

    rule {
      host = "${var.app_subdomain}.${var.domain_name}"

      http {
        # Route for backend API
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.backend.metadata[0].name
              port {
                number = 8000
              }
            }
          }
        }

        # Route for frontend (default)
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.frontend.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

output "ingress_tls_hostname" {
  description = "The ALB hostname for the TLS ingress"
  value       = try(kubernetes_ingress_v1.app_ingress_tls.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

# backend config map

# backend deployment

# backend service


# frontend deployment

# frontend service

# ingress