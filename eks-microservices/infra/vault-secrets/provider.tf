provider "aws" {
  region = var.region

  default_tags {
    tags = {
      repo = "k8sbootcamp-march26/eks-microservice-implementation"
    }
  }
}

provider "vault" {
  address          = var.vault_addr
  token            = var.vault_token
  skip_child_token = true
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}
