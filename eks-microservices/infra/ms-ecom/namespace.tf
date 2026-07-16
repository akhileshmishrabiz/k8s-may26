# Ecommerce workload namespace for microservices, databases, and ingress.
resource "kubernetes_namespace_v1" "ecommerce" {
  metadata {
    name = var.namespace
    labels = {
      app                            = "ecommerce"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "ecommerce"
    }
  }
}
