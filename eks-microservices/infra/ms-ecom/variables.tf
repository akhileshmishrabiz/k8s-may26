variable "cluster_name" {
  default = "eks-cluster"
}

variable "region" {
  default = "ap-south-1"
}

variable "namespace" {
  description = "Namespace where the ecommerce app is deployed"
  default     = "ecommerce"
}

variable "ingress_name" {
  default = "ecommerce-ingress"
}

variable "ingress_class_name" {
  default = "alb"
}

variable "alb_group_name" {
  description = "ALB group name — shared with other ingresses on the same ALB"
  default     = "k8sbatch-shared-alb"
}

variable "subdomain" {
  description = "Subdomain routed by the ingress"
  default     = "shop"
}

variable "domain_name" {
  description = "Main domain name"
  default     = "livingdevops.org"
}
variable "api_gateway_service_name" {
  default = "api-gateway"
}

variable "frontend_service_name" {
  default = "frontend"
}

variable "service_port" {
  default = 80
}

variable "acm_cert_arn" {
  description = "ACM certificate ARN"
  default     = "arn:aws:acm:ap-south-1:879381241087:certificate/d7c449d8-1540-4157-8959-bc48bb44b128"
}