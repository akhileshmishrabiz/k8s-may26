# argo application for 3-tier app
resource "kubernetes_manifest" "app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "devopsdozo"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/akhileshmishrabiz/k8s-may26.git"
        targetRevision = "argo-3tier"
        path           = "3-tier-app/k8s/menifests"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "3-tier-app-eks"
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}