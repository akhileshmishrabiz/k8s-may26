variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "eks-cluster"
}

variable "eks_cluster_version" {
  description = "The version of the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_cluster_endpoint_public_access" {
  description = "Whether to enable public access to the EKS cluster"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
  default     = "eks-vpc-may26"
}


variable "aws_region" {
  description = "The region of the AWS"
  type        = string
  default     = "ap-south-1"
}