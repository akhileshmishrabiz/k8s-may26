variable "cluster_name" {
  description = "EKS cluster name for the Kubernetes provider (one cluster per terraform apply)"
  default     = "eks-cluster"
}

variable "region" {
  default = "ap-south-1"
}

# Which environment this apply targets. Dev and prod are separate EKS clusters; each uses
# namespace ecommerce. Vault paths remain secret/ecommerce/<env>/... for credential isolation.
variable "env" {
  description = "Environment key (dev or prod) for Vault paths and ESO ExternalSecrets on this cluster"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for ESO ExternalSecrets (same name on every cluster)"
  type        = string
  default     = "ecommerce"
}

variable "environments" {
  description = "Deprecated: use var.env + var.namespace. Kept for Vault for_each compatibility."
  type = map(object({
    namespace = string
  }))
  default = {
    dev = {
      namespace = "ecommerce"
    }
    prod = {
      namespace = "ecommerce"
    }
  }
}

# Vault URL terraform talks to. Defaults to the public ALB at vault.livingdevops.org
# (deployed by eks/k8s-services/vault-eso/). Override for port-forward or other setups.
variable "vault_addr" {
  description = "Vault server address terraform writes secrets to"
  default     = "https://vault.devopsdozo.livingdevops.org/"
}

variable "vault_token" {
  description = "Vault auth token. Default is the dev-mode root token from eks/k8s-services/vault-eso/."
  default     = "root"
  sensitive   = true
}

# Address ESO uses to reach Vault from inside the cluster.
variable "vault_in_cluster_addr" {
  description = "Vault address as seen from inside the cluster (used by the ClusterSecretStore)"
  default     = "http://vault.vault.svc.cluster.local:8200"
}

variable "enable_eso_secrets" {
  description = "When true, also create the ClusterSecretStore + ExternalSecrets that bind ESO to Vault and materialise K8s secrets in each ecommerce namespace."
  type        = bool
  default     = true
}

variable "external_secrets_namespace" {
  default = "external-secrets"
}

variable "db_user" {
  default = "ecommerce_user"
}

variable "rabbitmq_user" {
  default = "rabbitmq"
}

# External-service credentials. Override via tfvars / -var when wiring real values.
variable "razorpay_key_id" {
  default   = "rzp_test_placeholder"
  sensitive = true
}

variable "razorpay_key_secret" {
  default   = "placeholder_secret_key"
  sensitive = true
}

variable "razorpay_webhook_secret" {
  default   = "whsec_placeholder"
  sensitive = true
}

variable "aws_access_key_id" {
  default   = "DSSffghffg"
  sensitive = true
}

variable "aws_secret_access_key" {
  default   = "wJalrasaasnFEMI/fggh/bPxRfiCYEXAMPLEKEY"
  sensitive = true
}
