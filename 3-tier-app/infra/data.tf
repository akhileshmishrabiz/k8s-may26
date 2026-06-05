data "aws_vpc" "eks_vpc" {
  filter {
    name = "tag:Name"
    values = [var.vpc_name]
  }
}


data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# data "aws_subnet_ids" "eks_subnet_ids" {
#   vpc_id = data.aws_vpc.eks_vpc.id
# }

# data "aws_subnet" "eks_subnet" {
#   id = data.aws_subnet_ids.eks_subnet_ids.ids[0]
# }