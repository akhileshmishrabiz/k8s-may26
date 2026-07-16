# Ecommerce workload namespace — one per cluster (same name "ecommerce" on dev and prod clusters).
#
# Apply per cluster:
#   terraform apply -var-file=env/dev.tfvars   # dev EKS cluster
#   terraform apply -var-file=env/prod.tfvars  # prod EKS cluster
#
# Isolation is by cluster, not namespace suffix.
resource "kubernetes_namespace_v1" "ecommerce" {
  count = var.enable_cluster_resources ? 1 : 0

  metadata {
    name = local.cluster_namespace
    labels = {
      app                            = "ecommerce"
      environment                    = local.cluster_env_label
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "ecommerce"
    }
  }
}
