# Maps each K8s secret the chart consumes to Vault paths under secret/ecommerce/.
locals {
  external_secrets = {
    "db-credentials" = [
      { secretKey = "POSTGRES_USER", key = "secret/data/ecommerce/database", property = "username" },
      { secretKey = "POSTGRES_PASSWORD", key = "secret/data/ecommerce/database", property = "password" },
      { secretKey = "username", key = "secret/data/ecommerce/database", property = "username" },
      { secretKey = "password", key = "secret/data/ecommerce/database", property = "password" },
    ]
    "redis-credentials" = [
      { secretKey = "REDIS_PASSWORD", key = "secret/data/ecommerce/redis", property = "password" },
    ]
    "rabbitmq-credentials" = [
      { secretKey = "RABBITMQ_DEFAULT_USER", key = "secret/data/ecommerce/rabbitmq", property = "username" },
      { secretKey = "RABBITMQ_DEFAULT_PASS", key = "secret/data/ecommerce/rabbitmq", property = "password" },
    ]
    "app-secrets" = [
      { secretKey = "JWT_SECRET", key = "secret/data/ecommerce/app", property = "jwt_secret" },
      { secretKey = "RAZORPAY_KEY_ID", key = "secret/data/ecommerce/razorpay", property = "key_id" },
      { secretKey = "RAZORPAY_KEY_SECRET", key = "secret/data/ecommerce/razorpay", property = "key_secret" },
      { secretKey = "RAZORPAY_WEBHOOK_SECRET", key = "secret/data/ecommerce/razorpay", property = "webhook_secret" },
    ]
    "aws-credentials" = [
      { secretKey = "AWS_ACCESS_KEY_ID", key = "secret/data/ecommerce/aws", property = "access_key_id" },
      { secretKey = "AWS_SECRET_ACCESS_KEY", key = "secret/data/ecommerce/aws", property = "secret_access_key" },
    ]
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = var.external_secrets_namespace
  }
}

data "kubernetes_namespace_v1" "ecommerce" {
  count = var.enable_eso_secrets ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "vault_token" {
  count = var.enable_eso_secrets ? 1 : 0

  metadata {
    name      = "vault-token"
    namespace = var.external_secrets_namespace
  }

  data = {
    token = var.vault_token
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "cluster_secret_store" {
  count = var.enable_eso_secrets ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "vault-backend"
    }
    spec = {
      provider = {
        vault = {
          server  = var.vault_in_cluster_addr
          path    = "secret"
          version = "v2"
          auth = {
            tokenSecretRef = {
              name      = "vault-token"
              key       = "token"
              namespace = var.external_secrets_namespace
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret_v1.vault_token]
}

resource "kubernetes_manifest" "external_secret" {
  for_each = var.enable_eso_secrets ? local.external_secrets : {}

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.key
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = each.key
        creationPolicy = "Owner"
      }
      data = [
        for entry in each.value : {
          secretKey = entry.secretKey
          remoteRef = {
            key      = entry.key
            property = entry.property
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.cluster_secret_store,
    data.kubernetes_namespace_v1.ecommerce,
  ]
}
