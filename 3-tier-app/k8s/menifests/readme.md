<!-- kubectl set image deployment/<deployment-name> <container-name>=<image>:<tag> -->
kubectl -n 3-tier-app-eks set image deployment/backend backend=879381241087.dkr.ecr.ap-south-1.amazonaws.com/3tier-devopsdozo-backend:8d5d9bff8f81d2a6ab1ca654e268cdfdb17436cf


kubectl -n 3-tier-app-eks set image deployment/frontend frontend=879381241087.dkr.ecr.ap-south-1.amazonaws.com/3tier-devopsdozo-frontend:8d5d9bff8f81d2a6ab1ca654e268cdfdb17436cf

kubectl  -n 3-tier-app-eks rollout status deployment/backend

kubectl  -n 3-tier-app-eks rollout status deployment/frontend 


###### ARGOCD deployment

Standard install on your EKS cluster:

1. Create the namespace.

```bash
kubectl create namespace argocd
```

2. Apply the install manifest. `stable` always points to the latest stable release.

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

For a production cluster you'd use the HA manifest instead (`manifests/ha/install.yaml`), but for your bootcamp/lab setup the standard one is fine.

3. Wait for the pods to come up.

```bash
kubectl wait --for=condition=available --timeout=300s \
  deployment --all -n argocd
```

Or just watch: `kubectl get pods -n argocd -w`.

4. Grab the initial admin password. It's auto-generated and stored in a secret.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Username is `admin`.

5. Access the UI. For a quick start, port-forward.

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open `https://localhost:8080`. You'll hit a self-signed cert warning, that's expected.

If you want it reachable without port-forward on EKS, patch the server to a LoadBalancer:

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

That provisions an AWS ELB in `ap-south-1`. Get the address with `kubectl get svc argocd-server -n argocd`. For anything real you'd front it with your ingress/ALB and a proper cert rather than exposing the ELB directly.

6. Install the CLI and log in (optional but worth it for scripting).

```bash
brew install argocd   # macOS, matches your setup
```

```bash
argocd login localhost:8080 --username admin \
  --password <password-from-step-4> --insecure
```

7. Change the admin password, then delete the bootstrap secret.

```bash
argocd account update-password
kubectl -n argocd delete secret argocd-initial-admin-secret
```

The initial secret is only needed for first login. Removing it is good hygiene.

One EKS-specific note: ArgoCD pods run on amd64 by default, which is fine on standard EKS node groups. If your cluster has any arm64 (Graviton) nodes mixed in, the official manifests are multi-arch so they'll schedule either way, no nodeSelector needed unlike your app images.

Want the next step after this, pointing ArgoCD at a Git repo to deploy your 3-tier app via an Application manifest?