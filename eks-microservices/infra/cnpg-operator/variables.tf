variable "cluster_name" {
  default = "eks-cluster"
}

variable "region" {
  default = "ap-south-1"
}

variable "cnpg_chart_version" {
  description = "CloudNativePG helm chart version"
  default     = "0.22.1"
}

variable "cnpg_namespace" {
  default = "cnpg-system"
}
