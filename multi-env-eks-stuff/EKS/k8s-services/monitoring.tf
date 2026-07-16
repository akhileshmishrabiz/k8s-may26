# ============================================================================
# Monitoring Stack - Prometheus & Grafana
# ============================================================================

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      name       = "monitoring"
      managed-by = "terraform"
    }
  }
}

resource "helm_release" "kube_prometheus_grafana_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "70.0.0"
  timeout    = 600

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
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
          retention         = "15d"
          retentionSize     = "10GB"
          serviceMonitorSelector          = {}
          serviceMonitorNamespaceSelector = {}
          podMonitorSelector              = {}
          podMonitorNamespaceSelector     = {}
          additionalScrapeConfigs         = []
          externalUrl                     = "https://prometheus.${var.app_subdomain}.${var.domain_name}"
          routePrefix                     = "/"
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
        }
        service = {
          type = "ClusterIP"
          port = 9090
        }
      }

      grafana = {
        enabled       = true
        adminPassword = "admin123"

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

        persistence = {
          enabled          = true
          storageClassName = "gp2"
          accessModes      = ["ReadWriteOnce"]
          size             = "10Gi"
        }

        service = {
          type = "ClusterIP"
          port = 80
        }

        sidecar = {
          datasources = {
            enabled                  = true
            defaultDatasourceEnabled = true
          }
        }

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

      nodeExporter = {
        enabled = true
      }

      kubeStateMetrics = {
        enabled = true
      }

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
    kubernetes_namespace_v1.monitoring,
  ]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "2.10.2"
  timeout    = 600

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
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_grafana_stack,
  ]
}

resource "kubernetes_ingress_v1" "grafana_ingress" {
  metadata {
    name      = "grafana-ingress"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
      "alb.ingress.kubernetes.io/certificate-arn"          = aws_acm_certificate.microservices_cert.arn
      "alb.ingress.kubernetes.io/healthcheck-path"         = "/api/health"
      "alb.ingress.kubernetes.io/healthcheck-protocol"     = "HTTP"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
      "alb.ingress.kubernetes.io/tags"                     = "Environment=production,ManagedBy=Terraform,Name=${var.app_subdomain}-ingress"
      "alb.ingress.kubernetes.io/group.name"               = var.alb_group_name
    }
  }

  spec {
    ingress_class_name = "alb"

    tls {
      hosts = ["grafana.${var.app_subdomain}.${var.domain_name}"]
    }

    rule {
      host = "grafana.${var.app_subdomain}.${var.domain_name}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.kube_prometheus_grafana_stack,
    aws_acm_certificate_validation.app,
    helm_release.aws_load_balancer_controller,
  ]
}

resource "kubernetes_ingress_v1" "prometheus_ingress" {
  metadata {
    name      = "prometheus-ingress"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
      "alb.ingress.kubernetes.io/certificate-arn"          = aws_acm_certificate.microservices_cert.arn
      "alb.ingress.kubernetes.io/healthcheck-path"         = "/-/healthy"
      "alb.ingress.kubernetes.io/healthcheck-protocol"     = "HTTP"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
      "alb.ingress.kubernetes.io/tags"                     = "Environment=production,ManagedBy=Terraform,Name=${var.app_subdomain}-ingress"
      "alb.ingress.kubernetes.io/group.name"               = var.alb_group_name
    }
  }

  spec {
    ingress_class_name = "alb"

    tls {
      hosts = ["prometheus.${var.app_subdomain}.${var.domain_name}"]
    }

    rule {
      host = "prometheus.${var.app_subdomain}.${var.domain_name}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-prometheus"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.kube_prometheus_grafana_stack,
    aws_acm_certificate_validation.app,
    helm_release.aws_load_balancer_controller,
  ]
}

resource "time_sleep" "wait_for_monitoring_ingress" {
  depends_on = [
    kubernetes_ingress_v1.grafana_ingress,
    kubernetes_ingress_v1.prometheus_ingress,
  ]

  create_duration = "120s"
}

data "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = kubernetes_ingress_v1.grafana_ingress.metadata[0].name
    namespace = kubernetes_ingress_v1.grafana_ingress.metadata[0].namespace
  }

  depends_on = [time_sleep.wait_for_monitoring_ingress]
}

resource "aws_route53_record" "grafana" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "grafana.${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = coalesce(
      try(data.kubernetes_ingress_v1.grafana.status[0].load_balancer[0].ingress[0].hostname, ""),
      kubernetes_ingress_v1.argocd_ingress_tls.status[0].load_balancer[0].ingress[0].hostname
    )
    zone_id                = var.aws_alb_zoneid
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.grafana]
}

resource "aws_route53_record" "prometheus" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "prometheus.${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = coalesce(
      try(data.kubernetes_ingress_v1.grafana.status[0].load_balancer[0].ingress[0].hostname, ""),
      kubernetes_ingress_v1.argocd_ingress_tls.status[0].load_balancer[0].ingress[0].hostname
    )
    zone_id                = var.aws_alb_zoneid
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.grafana]
}
