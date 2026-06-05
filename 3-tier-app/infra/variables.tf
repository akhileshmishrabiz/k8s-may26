variable "vpc_name" {
  description = "The ID of the VPC"
  type = string
  default = "eks-vpc-may26"
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type = string
  default = "eks-cluster"
}

variable "app_namepace" {
  description = "The name of the application namespace"
  type = string
  default = "3-tier-app-eks"
}

variable "domain_name" {
  description = "The domain name of the application"
  type = string
  default = "livingdevops.org"
}

variable "app_subdomain" {
  description = "The subdomain of the application"
  type = string
  default = "devopsdozo"
}