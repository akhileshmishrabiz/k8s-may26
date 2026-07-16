output "namespace" {
  description = "Ecommerce workload namespace"
  value       = kubernetes_namespace_v1.ecommerce.metadata[0].name
}

output "frontend_host" {
  description = "Primary frontend ingress host"
  value = try(
    local.ingress_services["frontend"].host,
    "${var.subdomain}.${var.app_subdomain}.${var.domain_name}"
  )
}

output "ingress_hosts" {
  description = "Resolved ingress host per service"
  value = {
    for key, cfg in local.ingress_services : key => cfg.host
  }
}

output "service_urls" {
  description = "HTTPS endpoint per service"
  value = {
    for key, cfg in local.ingress_services :
    key => "https://${cfg.host}${cfg.path == "/" ? "" : cfg.path}"
  }
}

output "ingress_names" {
  description = "Kubernetes ingress resource names per service"
  value = {
    for key, ing in kubernetes_ingress_v1.service : key => ing.metadata[0].name
  }
}

output "alb_group_name" {
  description = "Shared ALB ingress group name"
  value       = var.alb_group_name
}

output "acm_cert_arn" {
  description = "ACM certificate ARN used by ecommerce ingresses"
  value       = local.acm_cert_arn
}

output "argocd_app_name" {
  description = "ArgoCD Application name"
  value       = var.enable_argocd_app ? kubernetes_manifest.ecommerce[0].manifest.metadata.name : null
}

output "argocd_app_namespace" {
  description = "Namespace where the ArgoCD Application resource lives"
  value       = var.enable_argocd_app ? var.argocd_namespace : null
}

output "git_target_revision" {
  description = "Git branch ArgoCD tracks for the ecommerce Application"
  value       = var.git_target_revision
}

output "helm_chart_path" {
  description = "Git path ArgoCD uses for the services-only Helm chart"
  value       = var.helm_chart_path
}

output "argocd_destination_server" {
  description = "ArgoCD sync target cluster"
  value       = var.argocd_destination_server
}

output "cnpg_cluster_names" {
  description = "CNPG Cluster resources provisioned"
  value = {
    for key, cluster in kubernetes_manifest.cnpg_cluster : key => cluster.manifest.metadata.name
  }
}

output "data_store_services" {
  description = "In-cluster service names microservices connect to"
  value = concat(
    var.enable_databases && var.cnpg_enabled ? [for db in var.cnpg_databases : "${db}-rw"] : [],
    var.enable_databases && var.redis_enabled ? ["redis"] : [],
    var.enable_databases && var.rabbitmq_enabled ? ["rabbitmq"] : [],
  )
}
