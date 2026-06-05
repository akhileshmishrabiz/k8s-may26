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