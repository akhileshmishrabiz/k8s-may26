# ArgoCD Application — deploys the ecommerce Helm chart to the in-cluster namespace.
#
# Prerequisites (apply before this module):
#   - ArgoCD installed in var.argocd_namespace (EKS/k8s-services/argocd.tf)
#   - CNPG operator (EKS/k8s-services/cnpg.tf)
#   - Vault secrets + ESO ExternalSecrets (infra/vault-secrets/)
#   - ecommerce namespace (namespace.tf)
#
# ArgoCD deploys microservices, api-gateway, frontend, and seed job from
# eks-microservices/helm-services using helm-services/values.yaml.
# Ingress is managed by Terraform (ingress.tf), not Helm.
# Databases are NOT in the Helm chart — they are managed by Terraform.

locals {
  # Ingress is Terraform-owned (ingress.tf).
  argocd_helm_values = <<-EOT
    ingress:
      enabled: false
  EOT
}

resource "kubernetes_manifest" "ecommerce" {
  count = var.enable_argocd_app ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "ecommerce"
      namespace = var.argocd_namespace
      labels = {
        "app.kubernetes.io/name"       = "ecommerce"
        "app.kubernetes.io/part-of"    = "ecommerce"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      project = var.argocd_project
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_target_revision
        path           = var.helm_chart_path
        helm = {
          releaseName = "ecommerce"
          valueFiles  = [var.helm_values_file]
          values      = local.argocd_helm_values
        }
      }
      destination = {
        server    = var.argocd_destination_server
        namespace = var.namespace
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
