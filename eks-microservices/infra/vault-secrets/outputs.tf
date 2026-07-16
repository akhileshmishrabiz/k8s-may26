output "namespace" {
  description = "Target namespace for ecommerce secrets"
  value       = var.namespace
}

output "db_user" {
  value = var.db_user
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "redis_password" {
  value     = random_password.redis.result
  sensitive = true
}

output "rabbitmq_user" {
  value = var.rabbitmq_user
}

output "rabbitmq_password" {
  value     = random_password.rabbitmq.result
  sensitive = true
}

output "jwt_secret" {
  value     = random_password.jwt.result
  sensitive = true
}

output "vault_paths" {
  description = "KV v2 paths terraform writes to"
  value = [
    "secret/ecommerce/database",
    "secret/ecommerce/redis",
    "secret/ecommerce/rabbitmq",
    "secret/ecommerce/app",
    "secret/ecommerce/razorpay",
    "secret/ecommerce/aws",
  ]
}
