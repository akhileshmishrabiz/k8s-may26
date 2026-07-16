# Cluster-scoped config: one EKS cluster per terraform apply (var.env = dev | prod).
locals {
  cluster_env_cfg   = var.environments[var.env]
  cluster_namespace = local.cluster_env_cfg.namespace
  cluster_env_label = coalesce(try(local.cluster_env_cfg.environment_label, null), var.env)
}
