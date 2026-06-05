# private subnets

 # 2 private subnet for database
resource "aws_subnet" "rds_1" {
  cidr_block        = "10.0.5.0/24"
  availability_zone = "ap-south-1a"
  vpc_id            = data.aws_vpc.eks_vpc.id

  tags = {
    Name = "RDS Private Subnet 1"
  }
}

resource "aws_subnet" "rds_2" {
  cidr_block        = "10.0.6.0/24"
  availability_zone = "ap-south-1b"
  vpc_id            = data.aws_vpc.eks_vpc.id

  tags = {
    Name = "RDS Private Subnet 2"
  }
}


# subnet group (a group of subnets)
resource "aws_db_subnet_group" "postgres" {
  name        = "devopsdozo-rds-db-subnet-group"
  description = "Subnet group for RDS instance"
  subnet_ids = [
    aws_subnet.rds_1.id,
    aws_subnet.rds_2.id
  ]
  # subnet_ids =["subnet-0f42a1b9efaf4e602", "subnet-0395e32fc16981198"]

  tags = {
    Name        = "devopsdozo-db-subnet-group"
  }
}

# Generate the password for the database

resource "random_password" "db_password" {
  length           = 10
  special          = false
  override_special = "abcdgktyhtfAZVNNHDD1223434"
}

# create the rds instance

resource "aws_db_instance" "postgres" {
  identifier            = "devopsdozo-db"
  allocated_storage     = 10
  max_allocated_storage = 20
  engine                = "postgres"
  engine_version        = 14.15
  instance_class        = "db.t3.micro"
  username              = "postgres"
  password              = random_password.db_password.result
  port                  = 5432
  publicly_accessible   = false
  db_subnet_group_name  = aws_db_subnet_group.postgres.id
  ca_cert_identifier    = var.db_default_settings.ca_cert_name
  storage_encrypted     = true
  storage_type          = "gp3"
  kms_key_id            = aws_kms_key.env_kms.arn
  skip_final_snapshot   = true
  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  backup_retention_period    = 7
  db_name                    = "devopsdozodb"
  auto_minor_version_upgrade = true
  deletion_protection        = false
  copy_tags_to_snapshot      = true

  tags = {
    Name = "devopsdozo-db"
  }
}


# secret manager

resource "aws_secretsmanager_secret" "db_link" {
  name                    = "db/devopsdozo-db"
  description             = "DB link"
  recovery_window_in_days = 7
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "dbs_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_link.id
  secret_string = "postgresql://${var.db_default_settings.db_admin_username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"

  lifecycle {
    create_before_destroy = true
  }
}

# KMS key 

resource "aws_kms_key" "env_kms" {
  description             = "KMS key for RDS and Secrets Manager"
  deletion_window_in_days = 7

  tags = {
    Name        = "devopsdozo-rds-kms-key"
  }
}

resource "aws_kms_alias" "env_kms_alias" {
  name          = "alias/devopsdozo-rds-kms-key"
  target_key_id = aws_kms_key.env_kms.id
}