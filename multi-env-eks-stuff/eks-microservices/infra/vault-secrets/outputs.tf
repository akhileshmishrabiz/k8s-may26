output "env" {
  description = "Environment key for this cluster apply"
  value       = var.env
}

output "namespace" {
  description = "Target namespace for ecommerce secrets on this cluster"
  value       = var.namespace
}

output "namespaces" {
  description = "Target namespace keyed by env (same name on every cluster)"
  value = {
    (var.env) = var.namespace
  }
}

output "db_user" {
  value = var.db_user
}

output "db_passwords" {
  value = {
    for env_key, pwd in random_password.db : env_key => pwd.result
  }
  sensitive = true
}

output "redis_passwords" {
  value = {
    for env_key, pwd in random_password.redis : env_key => pwd.result
  }
  sensitive = true
}

output "rabbitmq_user" {
  value = var.rabbitmq_user
}

output "rabbitmq_passwords" {
  value = {
    for env_key, pwd in random_password.rabbitmq : env_key => pwd.result
  }
  sensitive = true
}

output "jwt_secrets" {
  value = {
    for env_key, pwd in random_password.jwt : env_key => pwd.result
  }
  sensitive = true
}

output "vault_paths" {
  description = "KV v2 paths terraform writes to for this cluster apply"
  value = [
    "secret/ecommerce/${var.env}/database",
    "secret/ecommerce/${var.env}/redis",
    "secret/ecommerce/${var.env}/rabbitmq",
    "secret/ecommerce/${var.env}/app",
    "secret/ecommerce/${var.env}/razorpay",
    "secret/ecommerce/${var.env}/aws",
  ]
}
