# eks cluster name


# vpc id
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

variable "eks_cluster_version" {
  description = "The version of the EKS cluster"
  type = string
  default = "1.31"
}

variable "awsloadbalancercontroller_sa" {
  description = "The name of the AWS Load Balancer Controller service account"
  type = string
  default = "aws-load-balancer-controller"
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

variable "prefix" {
  description = "The prefix of the application"
  type = string
  default = "3tier-devopsdozo"
}


## for cnpg 
variable "cnpg_chart_version" {
  description = "CloudNativePG helm chart version"
  default     = "0.22.1"
}

variable "cnpg_namespace" {
  default = "cnpg-system"
}

variable "aws_alb_zoneid" {
  default = "ZP97RAFLXTNZK"
}