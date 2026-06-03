Here's the updated assignment:

---

## Assignment: EKS Cluster Setup with Managed Node Group + Fargate Profile

**Objective:** Set up a production-style EKS cluster with proper networking, IAM, and node group configuration — fixing the exact issues we hit in class today. Then extend it with a Fargate profile and observe the difference.

---

### Task 1 — VPC & Networking Setup

You have two options here:

**Option A — Use default VPC (simpler)**
The default VPC only has public subnets. Fargate requires private subnets, so you need to add them manually:
- Create 2 private subnets in your default VPC across 2 different AZs
- Create a NAT Gateway in one of the existing public subnets
- Create a new route table, add route `0.0.0.0/0 → NAT Gateway`, associate it with both private subnets

**Option B — Create a custom VPC (recommended)**
- 2 public subnets and 2 private subnets across 2 AZs
- Internet Gateway attached and routed from public subnets
- NAT Gateway in one public subnet with route from private subnets

Either way, add these tags to all subnets:
- `kubernetes.io/cluster/<cluster-name>: shared`
- Private subnets also need: `kubernetes.io/role/internal-elb: 1`
- Public subnets also need: `kubernetes.io/role/elb: 1`

> NAT Gateway is mandatory for both Fargate and managed nodes running in private subnets. Without it, pods cannot pull container images, reach ECR, or talk to AWS APIs. This is exactly what broke our Fargate deployment in class when pods kept failing on image pull.

---

### Task 2 — IAM Roles

**Cluster IAM Role** — trust policy for `eks.amazonaws.com`, attach:
- `AmazonEKSClusterPolicy`

**Node IAM Role** — trust policy for `ec2.amazonaws.com`, attach all three:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`

> This is the exact reason our node group failed in class. The node IAM role was missing these policies. Nodes launched on EC2 but could not register with the cluster because they had no permission to call EKS APIs or pull images. Once you attach all three, the node group comes up cleanly.

**Fargate Pod Execution Role** — trust policy for `eks-fargate-pods.amazonaws.com`, attach:
- `AmazonEKSFargatePodExecutionRolePolicy`

---

### Task 3 — Security Group for EKS

Before creating the cluster, create a security group in your VPC with these inbound rules:

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 443 | TCP | Your IP / VPC CIDR | kubectl API access |
| 10250 | TCP | VPC CIDR | Kubelet communication |
| 1025-65535 | TCP | VPC CIDR | Control plane to node communication |
| All traffic | All | Same security group | Node to node communication |

Outbound: allow all.

> When you create the EKS cluster in the console, you provide this security group. This is the **cluster security group** — it controls who can talk to the control plane. The node group does NOT need you to assign a security group manually. EKS automatically assigns the cluster security group to all nodes in the node group. If you pick a wrong or restrictive SG during cluster creation, nodes will launch on EC2 but will never join the cluster because the required ports are blocked.

---

### Task 4 — EKS Cluster

Create via AWS Console:
- Kubernetes version 1.31+
- Control plane subnets: **private subnets**
- Attach the security group from Task 3
- Endpoint access: **Public and Private**
- Add-ons to install before moving forward: **VPC CNI**, CoreDNS, kube-proxy

> Install VPC CNI **before** creating the node group. In class, the node group was stuck in `CREATE_IN_PROGRESS` partly because VPC CNI was not present. Nodes need the CNI plugin to get pod networking configured on join.

---

### Task 5 — Managed Node Group

After cluster is `ACTIVE` and VPC CNI is installed:
- Subnets: **private subnets only**
- Instance type: `t3.medium`
- Desired: 2, Min: 1, Max: 3
- Attach the Node IAM Role from Task 2
- Leave the security group field blank — EKS will automatically assign the cluster SG to your nodes

Verify nodes joined:
```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get nodes
```

Both nodes should show `Ready` within 3-5 minutes. If they don't, check:
1. Node IAM role — all 3 policies attached?
2. VPC CNI addon — is it `Active`?
3. Security group — are the required ports open?

---

### Task 6 — Fargate Profile Setup

**Step 1 — Create namespace:**
```bash
kubectl create namespace fargate-apps
```

**Step 2 — Create Fargate Profile in Console:**
- Go to EKS → Cluster → Compute → Add Fargate Profile
- Name: `fargate-profile`
- Pod execution role: Fargate role from Task 2
- Subnets: **private subnets only — Fargate will not run on public subnets, this is a hard requirement from AWS**
- Namespace selector: `fargate-apps`

> If you try to select public subnets here the console will either block you or the pods will fail to schedule. Fargate runs pods on AWS-managed micro-VMs that only attach to private subnets. This is why we needed those private subnets and NAT Gateway from Task 1 — without them Fargate has nowhere to run and no way to pull images.

---

### Task 7 — Deploy on Fargate

Create `fargate-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-fargate
  namespace: fargate-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-fargate
  template:
    metadata:
      labels:
        app: nginx-fargate
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: "250m"
            memory: "64Mi"
```

```bash
kubectl apply -f fargate-deployment.yaml
kubectl get pods -n fargate-apps -w
```

> Notice the startup time. Fargate pods take 50-60 seconds to reach Running because AWS is provisioning a dedicated micro-VM per pod behind the scenes. This is the cold start cost of Fargate.

---

### Task 8 — Compare Managed Node vs Fargate

Deploy nginx on default namespace (managed nodes):
```bash
kubectl run nginx-managed --image=nginx
```

Answer these in your submission:
1. How long did the managed node pod take to reach `Running`?
2. How long did the Fargate pod take?
3. Run `kubectl get nodes` — what do the Fargate node names look like vs EC2 node names?
4. Run `kubectl describe pod nginx-fargate-<id> -n fargate-apps` — which node did it land on?

---

### Task 9 — Prove NAT Gateway is Required for Fargate

**Step 1** — Delete or disassociate the NAT Gateway route from your private subnet route table.

**Step 2** — Deploy a fresh pod in `fargate-apps`:
```bash
kubectl run nat-test --image=nginx -n fargate-apps
kubectl describe pod nat-test -n fargate-apps
```

Look at the Events section — you will see an image pull failure, same as what happened in class.

**Step 3** — Restore the NAT Gateway route and confirm the pod recovers.

> This is the proof that private subnets without a NAT Gateway cannot pull public images. The fix is either NAT Gateway for public images or VPC endpoints for ECR images. We will cover VPC endpoints in a later class.

---

### Cleanup

Delete in this exact order:

```bash
# Delete workloads first
kubectl delete deployment nginx-fargate -n fargate-apps
kubectl delete pod nginx-managed
kubectl delete pod nat-test -n fargate-apps
kubectl delete namespace fargate-apps
```

Then via console:
1. Fargate Profile
2. Node Group
3. EKS Cluster
4. NAT Gateway
5. Elastic IP attached to NAT Gateway
6. VPC (if custom) or private subnets (if default VPC)

> Always delete NAT Gateway and release the Elastic IP — these cost money even when idle. NAT Gateway is one of the most common sources of surprise AWS bills.

---

### Submission Checklist

- [ ] `kubectl get nodes` showing 2 managed nodes in `Ready` state
- [ ] Screenshot of all 3 policies attached to node IAM role
- [ ] Screenshot of security group with required ports open
- [ ] Screenshot of Fargate profile in `Active` state
- [ ] `kubectl get pods -n fargate-apps` showing pods in `Running` state
- [ ] Written answers to 4 comparison questions from Task 8
- [ ] Screenshot of image pull error from Task 9
- [ ] All resources deleted — no EC2, NAT Gateway, or EKS charges running

---

**Three things that must be right for nodes to join the cluster — node IAM role with all 3 policies, VPC CNI installed before node group creation, and security group with required ports open. Miss any one of them and nodes will appear healthy in EC2 but never show up in `kubectl get nodes`.**