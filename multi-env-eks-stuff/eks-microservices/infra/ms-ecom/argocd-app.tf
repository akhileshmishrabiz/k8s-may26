# ArgoCD Applications — one per environment (dev, prod), each syncing to a separate EKS cluster.
#
# Prerequisites (apply before this module):
#   - ArgoCD installed in var.argocd_namespace (EKS/k8s-services/argocd.tf)
#   - Target clusters registered in ArgoCD (environments.<env>.destination_server)
#   - CNPG operator on each target cluster (EKS/k8s-services/cnpg.tf)
#   - Vault secrets + ESO ExternalSecrets on each target cluster (infra/vault-secrets/)
#   - ecommerce namespace on each target cluster (namespace.tf applied per cluster)
#
# ArgoCD deploys microservices, api-gateway, frontend, and seed job from
# eks-microservices/helm-services using per-env value files.
# Ingress is managed by Terraform (ingress.tf), not Helm.
# Databases are NOT in the Helm chart — they are managed by Terraform.
#
# ArgoCD-only apply (e.g. from mgmt cluster): enable_cluster_resources=false

locals {
  argocd_environments = {
    for env, cfg in var.environments : env => {
      namespace          = cfg.namespace
      target_revision    = cfg.target_revision
      destination_server = cfg.destination_server
      values_file        = coalesce(try(cfg.values_file, null), "../environments/${env}/value.yaml")
      release_name       = coalesce(try(cfg.helm_release_name, null), "ecommerce-${env}")
      app_name           = coalesce(try(cfg.argocd_app_name, null), "ecommerce-${env}")
    }
  }

  # Ingress is Terraform-owned (ingress.tf).
  argocd_helm_values = <<-EOT
    ingress:
      enabled: false
  EOT
}

resource "kubernetes_manifest" "ecommerce" {
  for_each = var.enable_argocd_app ? local.argocd_environments : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.value.app_name
      namespace = var.argocd_namespace
      labels = {
        "app.kubernetes.io/name"         = "ecommerce"
        "app.kubernetes.io/part-of"    = "ecommerce"
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/environment" = each.key
      }
    }
    spec = {
      project = var.argocd_project
      source = {
        repoURL        = var.git_repo_url
        targetRevision = each.value.target_revision
        path           = var.helm_chart_path
        helm = {
          releaseName = each.value.release_name
          valueFiles  = [each.value.values_file]
          values      = local.argocd_helm_values
        }
      }
      destination = {
        server    = each.value.destination_server
        namespace = each.value.namespace
      }
      syncPolicy = merge(
        var.argocd_sync_automated ? {
          automated = {
            prune    = var.argocd_sync_prune
            selfHeal = var.argocd_sync_self_heal
          }
        } : {},
        var.argocd_sync_options != null ? {
          syncOptions = var.argocd_sync_options
        } : {}
      )
    }
  }

}
