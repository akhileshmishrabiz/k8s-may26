# Vault secrets + ESO for one cluster. Apply per cluster:
#   terraform apply -var-file=env/dev.tfvars
#   terraform apply -var-file=env/prod.tfvars
#
# Vault paths: secret/ecommerce/<env>/{database,redis,...} — env distinguishes dev/prod credentials.

locals {
  vault_envs = {
    (var.env) = {
      namespace = var.namespace
    }
  }
}
