# ============================================================================
# Monitoring Stack - Prometheus & Grafana
# ============================================================================
# This file deploys a complete monitoring solution using the kube-prometheus-stack
# which includes Prometheus, Grafana, Alertmanager, and various exporters

# Create namespace for monitoring components
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      name       = "monitoring"
      managed-by = "terraform"
    }
  }
}

# Deploy kube-prometheus-stack (includes Prometheus, Grafana, Alertmanager, and exporters)
resource "helm_release" "kube_prometheus_grafana_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "70.0.0"

  # Timeout increased for initial setup
  timeout = 600

  values = [
    yamlencode({
      # =======================
      # Prometheus Configuration
      # =======================
      prometheus = {
        prometheusSpec = {
          # Resource requests and limits
          resources = {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
          # Data retention
          retention     = "15d"
          retentionSize = "10GB"

          # Storage configuration
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "20Gi"
                  }
                }
              }
            }
          }

          # Service monitor selector - monitor all services in craftista namespace
          serviceMonitorSelector          = {}
          serviceMonitorNamespaceSelector = {}

          # Pod monitor selector
          podMonitorSelector          = {}
          podMonitorNamespaceSelector = {}

          # Additional scrape configs for custom metrics
          additionalScrapeConfigs = []

          # Configure Prometheus to work with subdomain
          externalUrl = "https://prometheus.${var.domain_name}"
          routePrefix = "/"
        }

        # Prometheus service configuration
        service = {
          type = "ClusterIP"
          port = 9090
        }
      }

      # =======================
      # Grafana Configuration
      # =======================
      grafana = {
        enabled = true

        # Admin credentials
        adminPassword = "admin123" # Change this in production!

        # Resource requests and limits
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }

        # Persistence for Grafana dashboards and data
        persistence = {
          enabled          = true
          storageClassName = "gp2"
          accessModes      = ["ReadWriteOnce"]
          size             = "10Gi"
        }

        # Grafana service configuration
        service = {
          type = "ClusterIP"
          port = 80
        }

        # Disable default datasource creation (we'll use the sidecar)
        sidecar = {
          datasources = {
            enabled                  = true
            defaultDatasourceEnabled = true
          }
        }

        # Add Loki as an additional datasource (Prometheus is provisioned by default)
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            access    = "proxy"
            url       = "http://loki.monitoring.svc.cluster.local:3100"
            isDefault = false
            editable  = true
          }
        ]

        # Pre-configured dashboards
        # dashboardProviders = {
        #   "dashboardproviders.yaml" = {
        #     apiVersion = 1
        #     providers = [
        #       {
        #         name            = "default"
        #         orgId           = 1
        #         folder          = ""
        #         type            = "file"
        #         disableDeletion = false
        #         editable        = true
        #         options = {
        #           path = "/var/lib/grafana/dashboards/default"
        #         }
        #       }
        #     ]
        #   }
        # }

        # Import common dashboards
        dashboards = {
          default = {
            kubernetes-cluster = {
              gnetId     = 7249
              revision   = 1
              datasource = "Prometheus"
            }
            kubernetes-pods = {
              gnetId     = 6417
              revision   = 1
              datasource = "Prometheus"
            }

          }
        }

        # Grafana ini configuration
        "grafana.ini" = {
          server = {
            domain              = "grafana.${var.app_subdomain}.${var.domain_name}"
            root_url            = "https://grafana.${var.app_subdomain}.${var.domain_name}"
            serve_from_sub_path = false
          }
          analytics = {
            check_for_updates = false
          }
        }
      }

      # =======================
      # Alertmanager Configuration
      # =======================
      #   alertmanager = {
      #     enabled = true

      #     alertmanagerSpec = {
      #       resources = {
      #         requests = {
      #           cpu    = "100m"
      #           memory = "128Mi"
      #         }
      #         limits = {
      #           cpu    = "200m"
      #           memory = "256Mi"
      #         }
      #       }

      #       storage = {
      #         volumeClaimTemplate = {
      #           spec = {
      #             storageClassName = "gp2"
      #             accessModes = ["ReadWriteOnce"]
      #             resources = {
      #               requests = {
      #                 storage = "5Gi"
      #               }
      #             }
      #           }
      #         }
      #       }
      #     }
      #   }

      # =======================
      # Node Exporter
      # =======================
      nodeExporter = {
        enabled = true
      }

      # =======================
      # Kube State Metrics
      # =======================
      kubeStateMetrics = {
        enabled = true
      }

      # =======================
      # Default Rules
      # =======================
      defaultRules = {
        create = true
        rules = {
          alertmanager                = true
          etcd                        = true
          configReloaders             = true
          general                     = true
          k8s                         = true
          kubeApiserverAvailability   = true
          kubeApiserverSlos           = true
          kubeControllerManager       = true
          kubelet                     = true
          kubeProxy                   = true
          kubePrometheusGeneral       = true
          kubePrometheusNodeRecording = true
          kubernetesApps              = true
          kubernetesResources         = true
          kubernetesStorage           = true
          kubernetesSystem            = true
          kubeSchedulerAlerting       = true
          kubeSchedulerRecording      = true
          kubeStateMetrics            = true
          network                     = true
          node                        = true
          nodeExporterAlerting        = true
          nodeExporterRecording       = true
          prometheus                  = true
          prometheusOperator          = true
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
  ]
}

# # ============================================================================
# # Ingress for Grafana UI
# # ============================================================================
# resource "kubectl_manifest" "grafana_ingress" {
#   yaml_body = yamlencode({
#     apiVersion = "networking.k8s.io/v1"
#     kind       = "Ingress"
#     metadata = {
#       name      = "grafana-ingress"
#       namespace = kubernetes_namespace.monitoring.metadata[0].name
#       annotations = {
#         # Create an internet-facing ALB (public access)
#         "alb.ingress.kubernetes.io/scheme" = "internet-facing"

#         # Use IP mode for better compatibility with Fargate and pod networking
#         "alb.ingress.kubernetes.io/target-type" = "ip"

#         # Health check path - ALB will check this endpoint for service health
#         "alb.ingress.kubernetes.io/healthcheck-path" = "/"

#         # SSL/TLS Configuration
#         # Listen on both HTTP (80) and HTTPS (443) ports
#         "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"

#         # Automatically redirect HTTP traffic to HTTPS
#         "alb.ingress.kubernetes.io/ssl-redirect" = "443"

#         # SSL Security Policy - ensures strong encryption
#         "alb.ingress.kubernetes.io/ssl-policy" = "ELBSecurityPolicy-TLS-1-2-2017-01"

#         # AWS ACM Certificate ARN - replace with your certificate ARN
#         # NOTE: Ensure this certificate covers your domain and is in the correct AWS region
#         "alb.ingress.kubernetes.io/certificate-arn" = var.acm_cert_arn

#         # HTTP to HTTPS redirect action configuration
#         "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": {\"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"

#         # Group name - all ingresses with the same group share a single ALB
#         "alb.ingress.kubernetes.io/group.name" = "k8sbatch-shared-alb"
#       }

#       labels = {
#         app        = "grafana"
#         managed-by = "terraform"
#       }
#     }
#     spec = {
#       ingressClassName = "alb"
#       tls = [
#         {
#           hosts      = ["grafana.${var.domain_name}"]
#           secretName = "grafana-tls"
#         }
#       ]
#       rules = [
#         {
#           host = "grafana.${var.domain_name}"
#           http = {
#             paths = [
#               {
#                 path     = "/"
#                 pathType = "Prefix"
#                 backend = {
#                   service = {
#                     name = "kube-prometheus-stack-grafana"
#                     port = {
#                       number = 80
#                     }
#                   }
#                 }
#               }
#             ]
#           }
#         }
#       ]
#     }
#   })

#   depends_on = [
#     helm_release.kube_prometheus_grafana_stack,
#   ]
# }

# ============================================================================
# Loki - Log aggregation (with Promtail as the log collector)
# ============================================================================
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "2.10.2"

  timeout = 600

  values = [
    yamlencode({
      loki = {
        enabled = true

        persistence = {
          enabled          = true
          storageClassName = "gp2"
          accessModes      = ["ReadWriteOnce"]
          size             = "20Gi"
        }

        config = {
          table_manager = {
            retention_deletes_enabled = true
            retention_period          = "168h"
          }
        }

        resources = {
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }

        service = {
          type = "ClusterIP"
          port = 3100
        }
      }

      promtail = {
        enabled = true

        config = {
          clients = [
            {
              url = "http://loki:3100/loki/api/v1/push"
            }
          ]
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      # We use Grafana from kube-prometheus-stack; disable bundled one
      grafana = {
        enabled = false
      }

      prometheus = {
        enabled = false
      }

      fluent-bit = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.kube_prometheus_grafana_stack,
  ]
}

# ============================================================================
# Ingress for Prometheus UI (Optional - for debugging)
# ============================================================================
# resource "kubectl_manifest" "prometheus_ingress" {
#   yaml_body = yamlencode({
#     apiVersion = "networking.k8s.io/v1"
#     kind       = "Ingress"
#     metadata = {
#       name      = "prometheus-ingress"
#       namespace = kubernetes_namespace.monitoring.metadata[0].name
#       annotations = {
#         # Create an internet-facing ALB (public access)
#         "alb.ingress.kubernetes.io/scheme" = "internet-facing"

#         # Use IP mode for better compatibility with Fargate and pod networking
#         "alb.ingress.kubernetes.io/target-type" = "ip"

#         # Health check path - ALB will check this endpoint for service health
#         "alb.ingress.kubernetes.io/healthcheck-path" = "/"

#         # SSL/TLS Configuration
#         # Listen on both HTTP (80) and HTTPS (443) ports
#         "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"

#         # Automatically redirect HTTP traffic to HTTPS
#         "alb.ingress.kubernetes.io/ssl-redirect" = "443"

#         # SSL Security Policy - ensures strong encryption
#         "alb.ingress.kubernetes.io/ssl-policy" = "ELBSecurityPolicy-TLS-1-2-2017-01"

#         # AWS ACM Certificate ARN - replace with your certificate ARN
#         # NOTE: Ensure this certificate covers your domain and is in the correct AWS region
#         "alb.ingress.kubernetes.io/certificate-arn" = var.acm_cert_arn

#         # HTTP to HTTPS redirect action configuration
#         "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": {\"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"

#         # Group name - all ingresses with the same group share a single ALB
#         "alb.ingress.kubernetes.io/group.name" = "k8sbatch-shared-alb"
#       }

#       labels = {
#         app        = "prometheus"
#         managed-by = "terraform"
#       }
#     }
#     spec = {
#       ingressClassName = "alb"
#       tls = [
#         {
#           hosts      = ["prometheus.${var.domain_name}"]
#           secretName = "prometheus-tls"
#         }
#       ]
#       rules = [
#         {
#           host = "prometheus.${var.domain_name}"
#           http = {
#             paths = [
#               {
#                 path     = "/"
#                 pathType = "Prefix"
#                 backend = {
#                   service = {
#                     name = "kube-prometheus-stack-prometheus"
#                     port = {
#                       number = 9090
#                     }
#                   }
#                 }
#               }
#             ]
#           }
#         }
#       ]
#     }
#   })

#   depends_on = [
#     helm_release.kube_prometheus_grafana_stack,
#   ]
# }