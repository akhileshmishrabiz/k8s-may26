variable "cluster_name" {
  description = "EKS cluster name for the Kubernetes provider"
  default     = "eks-cluster"
}

variable "region" {
  default = "ap-south-1"
}

variable "namespace" {
  description = "Kubernetes namespace for the ecommerce platform"
  type        = string
  default     = "ecommerce"
}

variable "subdomain" {
  description = "Frontend DNS host prefix (shop → shop.devopsdozo.livingdevops.org)"
  type        = string
  default     = "shop"
}

variable "environment_label" {
  description = "Environment tag for ALB ingress resources"
  type        = string
  default     = "production"
}

variable "app_subdomain" {
  description = "App DNS tier shared with ArgoCD/Vault/Grafana (e.g. devopsdozo → *.devopsdozo.livingdevops.org cert)"
  default     = "devopsdozo"
}

variable "aws_alb_zoneid" {
  description = "Route53 hosted zone ID for ALB alias targets (ap-south-1)"
  default     = "ZP97RAFLXTNZK"
}

variable "ingress_class_name" {
  description = "IngressClass name (AWS Load Balancer Controller uses alb)"
  default     = "alb"
}

variable "enable_ingress" {
  description = "Create ALB ingress resources for ecommerce services"
  type        = bool
  default     = true
}

variable "alb_group_name" {
  description = "ALB group name — shared with other ingresses on the same ALB (alb.ingress.kubernetes.io/group.name)"
  type        = string
  default     = "eksmay26-shared-alb"
}

variable "ingress_services" {
  description = <<-EOT
    Per-service ingress map. Keys become ingress resource names (<key>-ingress).
    Each service gets its own subdomain on the shared ALB:
    host = <host_prefix>.<app_subdomain>.<domain> (or explicit host override), path defaults to /.
    Frontend host_prefix defaults to var.subdomain when unset.
  EOT
  type = map(object({
    enabled          = optional(bool, true)
    host             = optional(string)
    host_prefix      = optional(string)
    path             = optional(string, "/")
    path_type        = optional(string, "Prefix")
    service_name     = string
    service_port     = number
    healthcheck_path = optional(string, "/health")
  }))
  default = {
    frontend = {
      host_prefix      = null
      service_name     = "frontend"
      service_port     = 80
      path             = "/"
      healthcheck_path = "/"
    }
    api-gateway = {
      host_prefix      = "api"
      service_name     = "api-gateway"
      service_port     = 80
      path             = "/"
      healthcheck_path = "/health"
    }
    product-service = {
      host_prefix      = "product"
      service_name     = "product-service"
      service_port     = 8001
      path             = "/"
      healthcheck_path = "/health"
    }
    user-service = {
      host_prefix      = "users"
      service_name     = "user-service"
      service_port     = 8002
      path             = "/"
      healthcheck_path = "/health"
    }
    cart-service = {
      host_prefix      = "cart"
      service_name     = "cart-service"
      service_port     = 8003
      path             = "/"
      healthcheck_path = "/health"
    }
    order-service = {
      host_prefix      = "orders"
      service_name     = "order-service"
      service_port     = 8004
      path             = "/"
      healthcheck_path = "/health"
    }
    payment-service = {
      host_prefix      = "payments"
      service_name     = "payment-service"
      service_port     = 8005
      path             = "/"
      healthcheck_path = "/health"
    }
    notification-service = {
      host_prefix      = "notifications"
      service_name     = "notification-service"
      service_port     = 8006
      path             = "/"
      healthcheck_path = "/health"
    }
  }
}

variable "domain_name" {
  description = "Main domain name"
  default     = "livingdevops.org"
}

variable "acm_cert_arn" {
  description = "Optional ACM certificate ARN override; defaults to ISSUED wildcard *.app_subdomain.domain from k8s-services"
  type        = string
  default     = null
}

variable "enable_argocd_app" {
  description = "Create the ArgoCD Application that deploys the ecommerce Helm chart"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed (from EKS/k8s-services/argocd.tf)"
  default     = "argocd"
}

variable "argocd_project" {
  description = "ArgoCD AppProject to deploy into"
  default     = "default"
}

variable "git_repo_url" {
  description = "Git repository ArgoCD pulls the Helm chart from"
  default     = "https://github.com/akhileshmishrabiz/k8s-may26.git"
}

variable "helm_chart_path" {
  description = "Path within the git repo to the ecommerce services-only Helm chart"
  default     = "eks-microservices/helm-services"
}

variable "helm_values_file" {
  description = "Helm values file relative to helm_chart_path"
  type        = string
  default     = "values.yaml"
}

variable "git_target_revision" {
  description = "Git branch or tag ArgoCD syncs for the ecommerce Application"
  type        = string
  default     = "main"
}

variable "argocd_destination_server" {
  description = "ArgoCD sync target (in-cluster default or registered cluster API URL)"
  type        = string
  default     = "https://kubernetes.default.svc"
}

variable "argocd_sync_automated" {
  description = "Enable automated sync (prune + selfHeal) for ArgoCD Applications"
  type        = bool
  default     = true
}

variable "argocd_sync_prune" {
  description = "Prune resources removed from git during automated sync"
  type        = bool
  default     = true
}

variable "argocd_sync_self_heal" {
  description = "Self-heal drift detected on live cluster resources"
  type        = bool
  default     = true
}

variable "argocd_sync_options" {
  description = "ArgoCD syncOptions for Applications. Namespaces are created by Terraform (namespace.tf), not ArgoCD."
  type        = list(string)
  default     = null
}

# ---------------------------------------------------------------------------
# Data stores (databases.tf) — provisioned via Terraform, not Helm
# ---------------------------------------------------------------------------

variable "enable_databases" {
  description = "Provision in-cluster CNPG clusters, Redis, and RabbitMQ"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "StorageClass for CNPG PVCs and RabbitMQ volumeClaimTemplates"
  default     = "gp2"
}

variable "image_pull_policy" {
  default = "IfNotPresent"
}

variable "cnpg_enabled" {
  type    = bool
  default = true
}

variable "cnpg_databases" {
  description = "CNPG Cluster resource names (also the PostgreSQL database name)"
  type        = list(string)
  default     = ["products", "users", "orders", "payments"]
}

variable "cnpg_instances" {
  default = 1
}

variable "cnpg_image" {
  default = "ghcr.io/cloudnative-pg/postgresql:15.4"
}

variable "cnpg_storage" {
  default = "1Gi"
}

variable "cnpg_db_owner" {
  description = "PostgreSQL owner created at CNPG bootstrap (must match vault-secrets db_user)"
  default     = "ecommerce_user"
}

variable "cnpg_enable_pod_monitor" {
  type    = bool
  default = false
}

variable "cnpg_postgresql" {
  type = object({
    max_connections      = string
    shared_buffers       = string
    effective_cache_size = string
    work_mem             = string
    maintenance_work_mem = string
  })
  default = {
    max_connections      = "100"
    shared_buffers       = "128MB"
    effective_cache_size = "256MB"
    work_mem             = "4MB"
    maintenance_work_mem = "64MB"
  }
}

variable "cnpg_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "redis_enabled" {
  type    = bool
  default = true
}

variable "redis_image" {
  default = "redis:7-alpine"
}

variable "redis_max_memory" {
  default = "256mb"
}

variable "redis_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "50m", memory = "64Mi" }
    limits   = { cpu = "250m", memory = "256Mi" }
  }
}

variable "rabbitmq_enabled" {
  type    = bool
  default = true
}

variable "rabbitmq_image" {
  default = "rabbitmq:3.12-management-alpine"
}

variable "rabbitmq_storage" {
  default = "1Gi"
}

variable "rabbitmq_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}
