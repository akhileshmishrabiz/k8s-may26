# Writes the ecommerce app secrets into Vault's KV v2 `secret/` mount.
# The mount is provisioned by Vault dev mode (eks/k8s-services/vault-eso/).

resource "vault_kv_secret_v2" "database" {
  mount               = "secret"
  name                = "ecommerce/database"
  delete_all_versions = true
  data_json = jsonencode({
    username = var.db_user
    password = random_password.db.result
  })
}

resource "vault_kv_secret_v2" "redis" {
  mount               = "secret"
  name                = "ecommerce/redis"
  delete_all_versions = true
  data_json = jsonencode({
    password = random_password.redis.result
  })
}

resource "vault_kv_secret_v2" "rabbitmq" {
  mount               = "secret"
  name                = "ecommerce/rabbitmq"
  delete_all_versions = true
  data_json = jsonencode({
    username = var.rabbitmq_user
    password = random_password.rabbitmq.result
  })
}

resource "vault_kv_secret_v2" "app" {
  mount               = "secret"
  name                = "ecommerce/app"
  delete_all_versions = true
  data_json = jsonencode({
    jwt_secret = random_password.jwt.result
  })
}

resource "vault_kv_secret_v2" "razorpay" {
  mount               = "secret"
  name                = "ecommerce/razorpay"
  delete_all_versions = true
  data_json = jsonencode({
    key_id         = var.razorpay_key_id
    key_secret     = var.razorpay_key_secret
    webhook_secret = var.razorpay_webhook_secret
  })
}

resource "vault_kv_secret_v2" "aws" {
  mount               = "secret"
  name                = "ecommerce/aws"
  delete_all_versions = true
  data_json = jsonencode({
    access_key_id     = var.aws_access_key_id
    secret_access_key = var.aws_secret_access_key
  })
}
