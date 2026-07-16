# Credentials — never committed.

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "redis" {
  length  = 24
  special = false
}

resource "random_password" "rabbitmq" {
  length  = 24
  special = false
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}
