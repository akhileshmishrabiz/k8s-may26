# output "ingress_name" {
#   value = kubernetes_ingress_v1.ecommerce.metadata[0].name
# }

# output "ingress_namespace" {
#   value = kubernetes_ingress_v1.ecommerce.metadata[0].namespace
# }

# output "app_url" {
#   value = "${var.subdomain}.${var.domain_name}"
# }

# output "alb_hostname" {
#   description = "ALB hostname assigned by aws-load-balancer-controller (populated after the ALB provisions)"
#   value       = try(kubernetes_ingress_v1.ecommerce.status[0].load_balancer[0].ingress[0].hostname, null)
# }

# # output "ecr_repository_urls" {
# #   description = "Map of ECR repo name -> repository URL"
# #   value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
# # }
