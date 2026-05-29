# Kubernetes Day 1 Assignment

**Bootcamp:** Real World Kubernetes on AWS  
**Topic:** Pods, Deployments, Services, ECR, and Secrets  
**Duration:** ~90 minutes

---

## Prerequisites

- Kind cluster running locally
- `kubectl` configured and pointing to the cluster
- AWS CLI configured with your credentials (`ap-south-1` region)
- Docker installed and running
- ECR repository created: `<your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app`

---

## Part 1 — Pods (20 mins)

### Task 1.1 — Create a Pod from a YAML file

Create a file `simple-pod.yaml` that defines an nginx pod and apply it.

```bash
kubectl create -f simple-pod.yaml
```

**Verify:**
```bash
kubectl get pod
kubectl describe pod nginx
kubectl logs nginx
```

**Questions:**
1. What is the STATUS of the pod after creation?
2. What node is the pod scheduled on? (hint: `kubectl get pod -o wide`)
3. What does `kubectl describe pod` show under the **Events** section?

---

### Task 1.2 — Delete and recreate the Pod

```bash
kubectl delete pod nginx
kubectl apply -f simple-pod.yaml
kubectl get pod
```

**Question:**  
What is the difference between `kubectl create -f` and `kubectl apply -f`? When would you use each?

---

## Part 2 — Deployments (20 mins)

### Task 2.1 — Create a Deployment

Create a `deployment.yaml` and apply it.

```bash
kubectl apply -f deployment.yaml
kubectl get deployments.apps
kubectl get pod
```

### Task 2.2 — Test self-healing

Delete one of the pods created by the deployment and observe what happens.

```bash
kubectl delete pod <pod-name>
kubectl get pod
```

**Questions:**
1. What happened after you deleted the pod?
2. How is a Deployment different from a standalone Pod?
3. What field in the deployment YAML controls how many replicas run?

---

## Part 3 — Services and Port Forwarding (15 mins)

### Task 3.1 — Create a Service

Create a `service.yaml` and apply it.

```bash
kubectl apply -f service.yaml
kubectl get service -o wide
```

### Task 3.2 — Access the app via port-forward

```bash
kubectl port-forward service/nginx-service 8800:8080
```

In a new terminal:

```bash
curl localhost:8800
```

**Questions:**
1. What is the purpose of `kubectl port-forward`? Is it suitable for production?
2. What is the difference between a `ClusterIP`, `NodePort`, and `LoadBalancer` service type?

---

## Part 4 — Build and Push to ECR (20 mins)

### Task 4.1 — Build your Docker image

Navigate to your app directory and build the image.

```bash
docker build -t kindapp .
docker images
```

### Task 4.2 — Tag and push to ECR

Authenticate Docker with ECR first:

```bash
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin \
  <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com
```

Tag and push:

```bash
docker tag kindapp <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app:1.0
docker push <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app:1.0
```

**Question:**  
Why do you need to authenticate before pushing to ECR? How long is the ECR token valid?

---

## Part 5 — ECR Image Pull Secret (15 mins)

### Task 5.1 — Create the docker-registry secret

```bash
kubectl create secret docker-registry ecr-secret \
  --docker-server=<your-account-id>.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-south-1) \
  --namespace=default
```

Verify:

```bash
kubectl get secrets
```

### Task 5.2 — Use the secret in your deployment

Update your deployment YAML to use the ECR image and reference the secret:

```yaml
spec:
  imagePullSecrets:
    - name: ecr-secret
  containers:
    - name: flask-app
      image: <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app:1.0
```

Apply and verify the pod comes up:

```bash
kubectl apply -f k8s/
kubectl get pod
kubectl logs <pod-name>
```

**Questions:**
1. What error do you see if `imagePullSecrets` is missing?
2. ECR tokens expire every 12 hours. What strategies can you use to handle token rotation in production?

---

## Part 6 — Exec into a Pod (5 mins)

### Task 6.1 — Shell into a running pod

```bash
kubectl exec -it <pod-name> -- sh
```

Once inside:

```bash
ls
env
cat /etc/os-release
exit
```

**Question:**  
Why would you need to exec into a pod? Name two real-world debugging scenarios where this is useful.

---

## Submission Checklist

- [ ] Pod created and verified with `describe` and `logs`
- [ ] Deployment self-healing tested and observed
- [ ] Service created and app accessed via port-forward
- [ ] Docker image built, tagged, and pushed to ECR
- [ ] `ecr-secret` created and used in deployment
- [ ] App running with ECR image confirmed via `kubectl get pod`
- [ ] Exec into pod and ran basic commands
- [ ] All questions answered

---

## Bonus Challenge

Encode and decode a string using base64 (as done in class):

```bash
echo "yourname" | base64
echo "<encoded-string>" | base64 --decode
```

Now inspect the raw content of your `ecr-secret`:

```bash
kubectl get secret ecr-secret -o yaml
```

**Question:**  
What is stored in the `.dockerconfigjson` key? Decode it and explain what you see.