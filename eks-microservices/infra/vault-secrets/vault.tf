# Writes ecommerce secrets into Vault's KV v2 `secret/` mount.
# Paths: secret/ecommerce/{database,redis,rabbitmq,app,razorpay,aws}

resource "vault_kv_secret_v2" "database" {
  disable_read = true
  mount        = "secret"
  name         = "ecommerce/database"
  data_json = jsonencode({
    username = var.db_user
    password = random_password.db.result
  })
}

resource "vault_kv_secret_v2" "redis" {
  disable_read = true
  mount        = "secret"
  name         = "ecommerce/redis"
  data_json = jsonencode({
    password = random_password.redis.result
  })
}

resource "vault_kv_secret_v2" "rabbitmq" {
  disable_read = true
  mount        = "secret"
  name         = "ecommerce/rabbitmq"
  data_json = jsonencode({
    username = var.rabbitmq_user
    password = random_password.rabbitmq.result
  })
}

resource "vault_kv_secret_v2" "app" {
  disable_read = true
  mount        = "secret"
  name         = "ecommerce/app"
  data_json = jsonencode({
    jwt_secret = random_password.jwt.result
  })
}

resource "vault_kv_secret_v2" "razorpay" {
  disable_read = true
  mount        = "secret"
  name         = "ecommerce/razorpay"
  data_json = jsonencode({
    key_id         = var.razorpay_key_id
    key_secret     = var.razorpay_key_secret
    webhook_secret = var.razorpay_webhook_secret
  })
}

resource "vault_kv_secret_v2" "aws" {
  disable_read = true
  mount        = "secret"
  name         = "ecommerce/aws"
  data_json = jsonencode({
    access_key_id     = var.aws_access_key_id
    secret_access_key = var.aws_secret_access_key
  })
}
