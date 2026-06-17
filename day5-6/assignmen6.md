# Assignment: Production EKS Cluster and 3-Tier App Deployment

This assignment covers everything we did across the last two classes. You are going to build a real EKS cluster the production way, deploy a 3-tier app on it, expose it to the internet with proper HTTPS, and fix the database migration the right way.

Do not rush this. Do each part, break things, fix them, and make notes of what failed and why. That is how you learn this in real life.

## What you are building

- A VPC with public and private subnets, one NAT gateway, and the right subnet tags for EKS.
- An EKS cluster with a managed node group, created with Terraform.
- A 3-tier app (frontend, backend, RDS Postgres) running inside the cluster.
- Service to service communication using cluster DNS.
- Internet access to the app using Ingress and the AWS Load Balancer Controller.
- HTTPS with an ACM certificate and a Route 53 record.
- A proper database migration that runs as a Kubernetes Job, not inside the app container.

## Prerequisites

- An AWS account with admin access for the labs.
- Terraform installed. Pin your version. We used 1.12.1 in class. If your local version is different, either change the version in versions.tf or use tfenv or tfswitch to match.
- kubectl, helm, and the AWS CLI installed and configured.
- A domain you control in Route 53. If you bought it from GoDaddy or Namecheap, create a public hosted zone and point the four name servers back to your registrar.

Keep your costs in mind. Delete the NAT gateway and scale node groups to zero when you are done for the day. Stop the RDS instance when you are not using it.

---

## Part 1: Create an EKS cluster manually from the console

Before we automate, do it by hand once so you understand what Terraform does for you later.

1. Create an EKS cluster from the console.
2. Add a managed node group and watch it fail to join. This is the bug we hit in class.
3. Fix it. For nodes to join the cluster you need three things at minimum:
   - The VPC CNI plugin installed.
   - A security group that allows inbound and outbound on port 443.
   - A node IAM role with these three policies attached: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, and AmazonEC2ContainerRegistryReadOnly.

Tasks:

- Get a node group into the Ready state with the correct IAM role.
- In class my nodes did not come up even with those three policies and I could not find the cause live. Try it yourself. If it works for you, write down exactly what your role, security group, and subnet settings were. If you find what was breaking my setup, tell me. That is part of the assignment.
- Explain in your own words the difference between a Fargate profile and a managed node group, and why a namespace matters for Fargate but not for a managed node group.

Once you understand this, delete the manual cluster. We do everything the production way from here.

---

## Part 2: EKS cluster with Terraform

Use a clean repo structure. Keep the cluster and the cluster services in separate folders. The cluster rarely changes. The services on top of it change often. Mixing them causes dependency cycles and messes during apply.

Suggested structure:

```
EKS/
  core-cluster/      # network + EKS cluster only
  k8s-services/      # load balancer controller, argocd, monitoring, vault, karpenter
```

### 2a. Network module

Build the network using the public VPC module from Terraform, terraform-aws-modules/vpc/aws.

Requirements:

- One VPC across three availability zones.
- Three private subnets and three public subnets.
- NAT gateway enabled, single NAT gateway only, to save cost in the lab. In real production you would run one NAT gateway per AZ for HA and to avoid cross zone traffic.
- DNS hostnames and DNS support enabled.
- Subnet tags for EKS discovery. This is the part people forget and then their load balancer never comes up. Public subnets need:
  - kubernetes.io/role/elb = 1
  - kubernetes.io/cluster/<cluster-name> = shared
  Private subnets need:
  - kubernetes.io/role/internal-elb = 1
  - kubernetes.io/cluster/<cluster-name> = shared

### 2b. EKS module

Use the public EKS module, terraform-aws-modules/eks/aws, version 21 or higher.

Requirements:

- Pass the VPC id and private subnet ids from your network module output. Do not hardcode subnet ids.
- Add the core add-ons: coredns, kube-proxy, and vpc-cni.
- Set the vpc-cni add-on to install before compute. If the CNI plugin is not ready before the nodes come up, the nodes wait forever and never join. This was a known bug in the older module versions.
- Enable public endpoint access so you can talk to the cluster from your laptop.
- Enable cluster creator admin permissions so the identity that deploys becomes the cluster admin.
- A managed node group with AL2023 x86_64 AMI, t3.medium instances, min 2, max 5, desired 2.

### 2c. State and version pinning

- Use an S3 backend for your state file. Use a separate state key for the core cluster and for the k8s-services folder.
- Use use_lockfile = true. No DynamoDB table needed.
- Hardcode the Terraform version. Do not use greater than. This forces everyone using your code to use the same version.

Tasks:

- terraform init, plan, then apply the core-cluster folder.
- Update your kubeconfig with: aws eks update-kubeconfig --name <cluster-name>
- Rename the context to something readable.
- Run kubectl get nodes and confirm your nodes are Ready.

---

## Part 3: RDS Postgres

Create a Postgres RDS instance for the app.

Requirements:

- Two private subnets for the database in a DB subnet group.
- A security group that allows port 5432 inbound. For the lab you can open it wide, but in production you allow only the EKS node security group. Note this difference in your README.
- Username postgres, set a database name, and a generated password.
- Keep the instance private. Do not make it publicly accessible.

Note the endpoint, database name, username, and password. You will map these into your app.

---

## Part 4: Deploy the 3-tier app with manifests

Use the manifests from the day5-6/k8s folder as your starting point. Build the backend and frontend images from the app folder, push them to your own ECR repositories, and update the image references.

Create these resources in the 3-tier-app-eks namespace:

- Namespace.
- Secret with the database credentials and the DATABASE_URL.
- ConfigMap with the non-sensitive config (DB host, DB name, DB port, Flask settings).
- Backend deployment with one replica. Include an init container that runs nslookup against your RDS endpoint and blocks until the database name resolves. If the init container exits non-zero, the backend never starts. Test both cases on purpose: put the wrong endpoint in and watch it hang, then fix it and watch it start.
- Backend service of type ClusterIP on port 8000.
- Frontend deployment with readiness and liveness probes on /health.
- Frontend service of type ClusterIP on port 80.

Tasks:

- Apply everything with kubectl apply -f .
- Confirm the init container completed with exit code 0 and the backend pod is Running.
- Port forward to the frontend and confirm the UI loads.
- You will need to update the database endpoint in three places: the secret, the backend manifest, and the configmap. Make sure all three point to your real RDS endpoint.

Common failures to debug here:

- Frontend cannot pull the image. You forgot to push the image to ECR or the tag is wrong.
- Backend init container hangs. Wrong RDS endpoint.
- Backend crashes with password authentication failed. Your secret password does not match the RDS password. Reset the RDS password to self managed and update the secret.
- App loads but cannot load topics. The database has no tables yet. We do the temporary migration fix in this lab and the proper fix in Part 8.

---

## Part 5: Service discovery with cluster DNS

Your frontend talks to the backend by name, not by IP. CoreDNS makes this work across the whole cluster.

Tasks:

- Explain the service DNS naming convention. A service named backend in namespace 3-tier-app-eks resolves at backend.3-tier-app-eks.svc.cluster.local.
- From inside a pod, run nslookup against your backend service full name and confirm it returns the service cluster IP.
- In your own words, write the Linux analogy. How is cluster DNS like /etc/hosts and /etc/resolv.conf on a normal Linux machine? What is the difference between a private cluster local name and a public DNS name?

---

## Part 6: Expose the app

We covered three service types. Use the right one.

- ClusterIP. Internal only. This is what your services should be.
- NodePort. Do not use in production. Know what it is for interviews and nothing else.
- LoadBalancer. Creates one cloud load balancer per service.

First, see why LoadBalancer type does not scale.

Tasks:

- Temporarily change the frontend service to type LoadBalancer and apply. Confirm an ALB is created and you can reach the app on the ALB hostname.
- Now reason about it. If you had 20 microservices, type LoadBalancer would create 20 load balancers, each needing its own domain mapping and certificate, all managed by hand. Write down why this is not practical.
- Revert the frontend service back to ClusterIP.

Then move to the production way: Ingress.

One Ingress rule creates one ALB and routes all your paths and hosts through it. But Ingress is just a rule. Something has to implement that rule. On AWS that something is the AWS Load Balancer Controller.

---

## Part 7: AWS Load Balancer Controller

This is the heart of the two days. You are connecting two worlds: the Kubernetes world and the AWS world. They need to authenticate to each other so that when you apply an Ingress, the controller can ask AWS to create an ALB.

The flow has three pieces:

1. An OIDC identity provider. Your EKS cluster comes with an OIDC issuer. AWS must trust it. If you created the cluster with Terraform or the console, this provider is already registered. Confirm it under IAM, Identity providers.
2. An IAM role with a trust policy that allows the controller service account to assume it with a web identity (IRSA). The role has a permissions policy that lets it create and manage load balancers, target groups, listeners, rules, and read EC2 and subnet tags.
3. The controller itself, installed with a Helm chart, using a service account annotated with the role ARN.

Do this in the k8s-services folder with Terraform.

### Provider and authentication setup

In providers.tf, configure the kubernetes and helm providers to authenticate to the cluster. Use data sources to pull the cluster endpoint, the CA certificate, and a temporary auth token. This is the same thing kubectl does when it reads your kubeconfig, just done from Terraform.

In data.tf, add data sources for:

- aws_eks_cluster
- aws_eks_cluster_auth
- aws_iam_openid_connect_provider, using the cluster OIDC issuer URL
- aws_vpc, filtered by your VPC name tag

### IAM role and policy

- Create an IAM role whose trust policy allows sts:AssumeRoleWithWebIdentity from your OIDC provider, scoped to the controller service account in kube-system. Pin both the :sub condition to system:serviceaccount:kube-system:<sa-name> and the :aud condition to sts.amazonaws.com.
- Create the IAM policy with the full AWS Load Balancer Controller permission set and attach it to the role.

### Helm release

- Install the aws-load-balancer-controller chart from https://aws.github.io/eks-charts into kube-system.
- Set clusterName, region, vpcId, serviceAccount.create to true, the service account name, and the service account role-arn annotation pointing to your IAM role.
- Make the helm release depend on the policy attachment.

Tasks:

- Apply and confirm the controller pods are running in kube-system.
- Run kubectl get serviceaccounts -n kube-system and confirm your service account exists with the role annotation.
- Explain in one paragraph the difference between SAML, OAuth, and OIDC, and why Kubernetes uses OIDC to talk to AWS.

---

## Part 8: Ingress and HTTPS

Now wire the app to the internet through one ALB with proper TLS.

### Certificate

- Request an ACM certificate for your subdomain, for example devopsdozo.yourdomain.org, with DNS validation.
- Create the Route 53 validation records and wait for the certificate to validate.

### Ingress

Create an Ingress in the app namespace with these ALB annotations:

- scheme internet-facing
- target-type ip
- listen-ports for HTTP 80 and HTTPS 443
- ssl-redirect to 443
- certificate-arn pointing to your validated ACM certificate
- healthcheck-path /health

Define routing rules:

- Path /api to the backend service on port 8000.
- Path / to the frontend service on port 80.

### DNS record

- Create a Route 53 alias A record for your subdomain pointing to the ALB hostname created by the Ingress.

Tasks:

- Apply and wait for the ALB to provision.
- Hit https://yoursubdomain and confirm the app loads over HTTPS with a valid certificate.
- Confirm HTTP redirects to HTTPS.

---

## Part 9: Database migration the proper way

In the lab we did a temporary fix by running migrate.sh from the Docker entrypoint. That is wrong for production. Now fix it properly.

Think about why the temporary approaches are bad:

- Migration inside the app container, with many replicas, means every replica races to create the same schema against the same database at the same time.
- Migration in an init container has the same problem. The init container runs once per pod, so 20 pods means 20 migration attempts.

The right way:

- Keep the migration script in the image but do not run it on container start.
- Run the migration as a one time Kubernetes Job, separate from the deployment.
- In your pipeline, run the migration Job and wait for it to complete successfully before you roll out the new backend pods.
- Keep schema changes version controlled so you can roll back the schema first, then the app, and keep them compatible.

Tasks:

- Comment out the migration command in the backend Dockerfile so the app no longer migrates on start.
- Write a Kubernetes Job that uses the same backend image with a different startup command to run the migration.
- Run the Job, confirm it completes, then deploy the backend with one or more replicas and confirm the app works with no race.
- Write a short note on how you would trigger this Job from a CI/CD pipeline before the deployment step.

---

## Bonus tasks

These are optional but they are what separates you in interviews.

1. Network module pull request. Take my custom network module and add support for setting tags on the subnets, so it works cleanly with EKS subnet discovery. Open a pull request against the repo.
2. Convert the whole app deployment to Terraform. Instead of raw manifests, manage the namespace, secret, configmap, services, and Ingress with the kubernetes provider, and generate the secret values and DB password with the random provider so no credentials sit in any file. Pull the DB endpoint, port, name, and username straight from the RDS resource attributes.
3. Karpenter. Replace cluster autoscaler thinking with Karpenter. Add a node pool and explain how Karpenter spins up nodes on demand when pods cannot be scheduled, and how that is smarter than an EC2 autoscaling group tied to a node group.
4. Explain the node group to autoscaling group to EC2 chain. Show where the launch template and autoscaling group live for a managed node group, and how you would do an instance refresh to rotate unhealthy nodes.

---

## Submission

Submit:

- Your Terraform code for core-cluster, k8s-services, and the app.
- Your Kubernetes manifests or the Terraform that replaces them.
- A README with screenshots showing: nodes Ready, app reachable over HTTPS, controller pods running, and the migration Job completed.
- Your notes on every failure you hit and how you fixed it.

If something breaks and you cannot fix it, do not skip it. Write down what you tried and bring it to the next class.