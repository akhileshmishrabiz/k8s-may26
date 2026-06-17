# Assignment : Ingress, Full Terraform, and the Infra Pipeline

This is the second part. The first assignment got you a cluster and an app running, with the load balancer controller and a first look at Ingress. These two classes finish the Ingress and HTTPS story properly, then move everything we did by hand into Terraform, and start building the CI/CD pipeline that deploys it all.

Same rule as before. Do every part. Break things on purpose. Write down what failed and how you fixed it.

A note before you start. There is almost no new concept in the second half of this work. It is the same things we already did, just moved into Terraform and into a pipeline. If a part feels hard, it is because the concept was not solid the first time. Go back to the recording for that piece before you move on.

## What you are finishing

- Ingress with the AWS Load Balancer Controller, HTTP first, then HTTPS.
- ACM certificate and a Route 53 record so the app is live on your domain over TLS.
- Everything we did manually moved into Terraform: RDS, KMS, Secrets Manager, the certificate, the Route 53 record, and the Kubernetes resources.
- Proper secret handling with no hardcoded base64 in any file.
- A GitHub Actions workflow that runs your infra apply and destroy.
- A build pipeline that builds the backend and frontend images and pushes them to ECR.

## The deployment order, memorize this

Everything depends on the cluster existing first. If you apply out of order, it breaks badly. The order is always:

1. EKS/core-cluster. The network and the EKS cluster.
2. EKS/k8s-services. The AWS Load Balancer Controller.
3. 3-tier-app/infra. The database, certificate, Route 53, and the Kubernetes resources.
4. Your app manifests, or the Terraform that replaces them.

If your nodes are scaled to zero from last time, scale them back up first. And if you deleted the NAT gateway to save cost, bring it back before you apply the controller, because the pods need egress.

---

## Part 1: Custom resources and operators

When you installed the load balancer controller, it did more than create a few pods. It added new resource types to your cluster.

Tasks:

- Run a command to list the custom resource definitions in your cluster and find the ones that came from the controller, for example the ELBV2 group.
- In your own words, explain what a controller or operator is and what a control loop does. Core Kubernetes runs a control loop on its own built in resources like Deployments, which is why a Deployment keeps the right number of pods alive. An operator gives that same control loop behavior to a third party tool.
- Explain why the Kubernetes ecosystem matters more than the core. Core Kubernetes is small. The reason it runs in production everywhere is the ecosystem of operators: Argo CD for deployment, CNPG for databases, Karpenter for node scaling, the load balancer controller for ingress. Name two more operators you have heard of and what they do.

---

## Part 2: Ingress, the HTTP version first

Start simple so you can see each piece work before you add TLS.

Background to get right first:

- The IngressClass. Your Ingress must reference a class. The alb class is created for you when the controller installs. The class tells Kubernetes which controller implements the rule. Confirm the alb IngressClass exists.
- Subnet tags. The controller finds where to place the ALB using subnet tags. Public subnets need kubernetes.io/role/elb = 1. If this tag is missing, the ALB never comes up. This is the single most common reason an Ingress hangs. Confirm the tag is on your public subnets.
- Annotations versus labels. Labels identify and select. Annotations turn on behavior. The ALB settings all go in annotations.

Build an HTTP only Ingress in the app namespace:

- ingressClassName alb
- annotation scheme internet-facing
- annotation target-type ip, because you are routing to pod IPs
- annotation healthcheck-path /health
- one rule, path / to the frontend service on port 80

Tasks:

- Apply it and watch the ALB provision.
- Open the controller pod logs and find the successful reconcile message. That message is your signal the ALB was created. When something is wrong, the reason shows up in these logs. Get in the habit of reading them.
- Look at the security groups on the ALB. You did not create them. The controller did. Note that only the HTTP port is open right now, because you only configured HTTP.
- Hit the ALB hostname directly and confirm the app loads, not secure.

---

## Part 3: Ingress with HTTPS

Now do it the way you will actually ship it.

### Certificate

- Request an ACM certificate for your subdomain with DNS validation, or reuse the one from the first assignment.
- Keep export disabled on the certificate. An exportable certificate costs money. A normal one does not. Note this in your README.
- Optional but worth trying: request a wildcard certificate for *.yourdomain so one certificate covers every subdomain. You will want this when you reach microservices.

### Ingress

Create a second Ingress, or extend the first, with the TLS pieces added:

- annotation listen-ports for HTTP 80 and HTTPS 443
- annotation ssl-redirect 443, so anyone hitting HTTP is sent to HTTPS
- annotation certificate-arn pointing to your validated certificate
- a tls block and a rule host set to your full subdomain

### Route 53

- Create a Route 53 alias A record for your subdomain pointing to the ALB. The Ingress alone does not map your domain. You have to point the domain at the ALB.

Tasks:

- Apply, wait for the ALB, then hit https://yoursubdomain and confirm valid TLS.
- Confirm HTTP redirects to HTTPS.
- Run nslookup against the ALB hostname and explain why you get more than one IP. The number of IPs matches the number of subnets the ALB spans. That is how it survives an AZ going down.
- Delete the Ingress and watch the ALB get removed too. Then re-apply. Understand that the ALB lifecycle follows the Ingress.

A teaching note from class: I kept a plain HTTP Ingress file commented out next to the HTTPS one, only so you can see the simple version. In real life you keep the HTTPS one. Do not ship the plain HTTP version.

---

## Part 4: One ALB for many services

You will not create one load balancer per service. That does not scale.

Tasks:

- Explain the two ways to keep many services behind one ALB:
  1. One Ingress with multiple path or host rules.
  2. Multiple Ingress resources that share the alb group annotation, so they all attach to the same ALB.
- Add a second rule to your Ingress that routes /api to the backend service on port 8000, while / still goes to the frontend. Confirm both work through the single ALB.

---

## Part 5: CORS, why the browser blocks your backend

When the frontend in the browser calls the backend, modern browsers only allow it if the backend says that origin is allowed.

Tasks:

- Set an allowed origins value on the backend config so it accepts requests from your HTTPS subdomain and, if needed, the HTTP version.
- In your own words, explain what CORS protects against and why the allowed origins live on the backend, not the frontend.

---

## Part 6: Move everything into Terraform

This is the heart of the second class. We did a lot by hand. Now none of it should be manual. Create a 3-tier-app/infra folder and move the whole app stack into Terraform.

Set up the providers and data sources first:

- providers.tf with the aws, kubernetes, and helm providers. The kubernetes and helm providers authenticate to the cluster using the cluster endpoint, the CA certificate, and the auth token pulled from data sources. This is the same authentication you set up for the k8s-services folder.
- data.tf with data sources for the cluster, the cluster auth, the OIDC provider, and the VPC looked up by its name tag.
- versions.tf with pinned versions and an S3 backend with use_lockfile = true. Use a separate state key from the cluster and the services.

Then build these resources:

### RDS, in its own subnets

- Create two private subnets inside the existing VPC just for the database, for isolation and security. Put them in a DB subnet group.
- A security group allowing 5432. For the lab you can open it wide. In production you allow only the EKS node security group. Note the difference.
- The Postgres instance, version 17.5, encrypted with a KMS key.

### KMS and Secrets Manager

- Create a KMS key and an alias for it. Use it to encrypt the database.
- Store the full database connection string in AWS Secrets Manager. This is how a real team keeps the credential out of code.

### Passwords with the random provider

- Add the random provider and generate the database password and the app secret key. Never hardcode a password. Never commit one. This is the whole point. After this part there should be no credential sitting in any file.

### Kubernetes resources

- Create the namespace, the backend ConfigMap and Secret, the frontend ConfigMap, and the backend and frontend services, all in Terraform using the kubernetes provider.
- Map the database host, port, name, username, and password straight from the RDS resource attributes and the random password. Nothing typed by hand.

### Certificate and route, in Terraform

- In cert.tf, pull the public hosted zone, create the ACM certificate, create the validation records, and run the certificate validation resource.
- Create the Route 53 alias record pointing to the ALB created by the Ingress.

### Ingress in Terraform

- Recreate the HTTPS Ingress as a kubernetes_ingress_v1 resource with the same annotations, the two path rules, and a depends_on for the namespace and the certificate validation.

A decision to understand and write down: we deploy the fixed infrastructure with Terraform, the namespace, secrets, config, services, certificate, route, and Ingress. We do not deploy the application image rollout with Terraform. The app changes constantly as the team ships features, so that belongs to Argo CD, which is next class. Explain in a sentence why the app rollout does not belong in Terraform.

Tasks:

- terraform init, plan, apply the 3-tier-app/infra folder.
- Confirm the app is live over HTTPS with everything created by Terraform and zero manual console steps.

---

## Part 7: Terraform state lock troubleshooting

You will hit this. When an apply is interrupted, the state stays locked in the S3 bucket and the next run refuses to start.

Tasks:

- Cause a lock on purpose, for example by killing an apply midway.
- Resolve it from the command line with the force unlock command and the lock ID, not by poking around the console.
- Write down why a state lock exists in the first place and why you should be sure no one else is applying before you force unlock.

---

## Part 8: The infrastructure pipeline with GitHub Actions

Now stop running Terraform from your laptop. Build a workflow that runs it.

Build a workflow_dispatch workflow so you trigger it manually and pass inputs:

- An input for the path to apply, so you can target core-cluster, k8s-services, or the app infra.
- An input to choose the action, apply or destroy. Destroy matters in the bootcamp because you want to tear the cluster down to save cost.
- Inputs for the Terraform version and the AWS region, so the same workflow works across environments.

The steps the job needs:

- Check out the code.
- Set up Terraform at the chosen version.
- Configure AWS credentials on the runner. For now use an access key and secret key stored in GitHub Secrets. We will replace this with OIDC based dynamic access next week, which is the proper way. For now, know that the keys are the weak point.
- Run init, then plan, then the chosen apply or destroy in the chosen path.

Tasks:

- Run the workflow to deploy the core cluster, then the services, then the app infra, in order, by passing the path each time.
- Be careful with the region variable so the code stays correct across environments. A wrong region is a very common pipeline mistake.
- Write a short note on why storing long lived access keys in GitHub Secrets is risky and what OIDC will give you instead.

---

## Part 9: The application build pipeline

The infra pipeline builds infrastructure. This one builds and ships the app images.

Tasks:

- Provision the backend and frontend ECR repositories with Terraform, not by hand.
- Build both images with Docker Buildx.
- Tag each image with the GitHub commit SHA, not latest. The commit SHA gives you a unique, traceable version so you always know exactly which code is running. Explain why latest is a bad tag in production.
- Push both images to their ECR repositories.
- Read about matrix builds and write two or three sentences on how a matrix would let one workflow build many service images in parallel once you move to microservices. You do not have to implement it yet.

---

## Part 10: The open problem, ALB zone ID

When the Route 53 alias points at the ALB, it needs the ALB hosted zone ID. That zone ID is specific to the ALB and it changes by region, for example it is one value in ap-south-1 and different elsewhere.

In class I hardcoded the zone ID to keep moving, but that ties the code to one region.

Tasks:

- Get the deployment working with a hardcoded zone ID first.
- Then find a dynamic way to resolve the ALB zone ID so the code is not region locked. This is a real assignment, not a throwaway. Bring your approach to the next class.

---

## Looking ahead, so you can prepare

Next class moves to a Kind cluster, Kubernetes in Docker, so we can teach the harder pieces without paying for EKS all day. The big topics coming are:

- Packaging the 3-tier app into a Helm chart instead of raw manifests.
- Argo CD for the application deployment.
- Database migrations run as a proper Kubernetes Job, not from the app container, which you started in the first assignment.
- Secret management the professional way with HashiCorp Vault and the External Secrets Operator, so credentials come from an external provider into the cluster at runtime.

To get ready, make sure Helm clicked. A lot of people got stuck on it in class, so be clear on this distinction before next week: a Docker image is one running application component, one container. A Helm chart is a package that can deploy many components, many images, many resources, with one command and your own config values. The chart is not the image. The chart deploys things that use images. Write that difference in your own words. If you cannot, watch a thirty minute Helm basics video and try again.

---

## Submission

Submit:

- The 3-tier-app/infra Terraform that creates the database, KMS, Secrets Manager, certificate, route, and Kubernetes resources with no hardcoded credentials.
- Your GitHub Actions infra workflow and the build workflow.
- Screenshots showing: the app live over HTTPS on your domain, the controller pods running, the successful reconcile log line, the custom resources from the controller, and your images in ECR tagged by commit SHA.
- Your write up for every reflection question above, plus your approach to the ALB zone ID problem.
- Your notes on every failure you hit, including the state lock and how you cleared it.

If something does not work and you cannot fix it, do not skip it. Write down what you tried and bring it next week.