# OpenTelemetry on AWS EKS

This repository combines the OpenTelemetry Demo microservices with Terraform
configuration for an AWS VPC and EKS cluster. Run the demo locally with Docker
Compose, or provision the AWS infrastructure and deploy the Kubernetes
application.

## Repository map

- `docker-compose.yml` and `.env` — local demo and its default settings.
- `src/` — demo microservices and supporting applications.
- `kubernetes/complete-deploy.yaml` — Kubernetes services, deployments, and
  configuration for the demo application.
- `main.tf`, `module/`, and `variables.tf` — AWS VPC and EKS infrastructure.
- `backend/` — Terraform state bucket bootstrap configuration.
- `.github/workflows/ci.yaml` — Product Catalog build and CI/CD workflow.

## Prerequisites

For the local run:

- Docker Desktop with Docker Compose v2.
- Git.

For the AWS run, in addition:

- An AWS account and AWS CLI configured with credentials that can create the
  VPC, EKS cluster, IAM roles, node group, and S3 bucket in this configuration.
- Terraform 1.10 or newer and `kubectl`. The S3 backend configuration enables
  Terraform's S3 lockfile support.
- AWS service quotas and budget sufficient for an EKS cluster, EC2 nodes, and
  NAT gateways. The VPC configuration creates three NAT gateways, which incur
  ongoing charges.

Run commands below from the repository root. PowerShell can be used on Windows.

## Option 1: Run the complete demo locally

1. Start and build the services:

   ```powershell
   docker compose up --build --detach
   ```

   The first run can take a while while Docker downloads and builds images.

2. Check service status and, if needed, inspect startup logs:

   ```powershell
   docker compose ps
   docker compose logs --follow
   ```

3. Open the demo and observability interfaces:

   - Storefront: <http://localhost:8080>
   - Load generator: <http://localhost:8080/loadgen/>
   - Grafana: <http://localhost:3000>
   - Jaeger: <http://localhost:16686>

   The Compose configuration also starts the OpenTelemetry Collector,
   Prometheus, and OpenSearch services. The load generator produces demo
   traffic; browse the storefront and place an order to exercise the
   microservices.

4. Stop the services:

   ```powershell
   docker compose down
   ```

   To also remove Compose-managed data volumes and reset local data, use
   `docker compose down --volumes`.

## Option 2: Provision AWS EKS and deploy the application

### 1. Configure AWS access

Configure the AWS CLI for the account and region used by the Terraform
configuration (`ap-south-1` by default), then verify your identity:

```powershell
aws sts get-caller-identity
```

The Terraform files currently hard-code the remote state bucket name
`terraform-eks-state-s3-bucket-011110`. It must be globally unique and available
in the account. If you use a different bucket, update the bucket name in both
`main.tf` and `backend/backend.tf` before continuing.

### 2. Create the Terraform state bucket (one time)

The root Terraform configuration stores state in S3, so create that bucket
before initializing the root configuration. Skip this step if the configured
bucket already exists and is accessible to your AWS credentials.

```powershell
terraform -chdir=backend init
terraform -chdir=backend plan
terraform -chdir=backend apply
```

Review the plan and confirm the apply when prompted. This bootstrap
configuration uses local Terraform state; retain that state file for future
changes to the bucket.

### 3. Provision the VPC and EKS cluster

```powershell
terraform init
terraform validate
terraform plan
terraform apply
```

Review the plan before confirming. Terraform creates the VPC, public and
private subnets, NAT gateways, EKS control plane, IAM roles, and managed node
group. Defaults are in `variables.tf`; for a different cluster name, region,
Kubernetes version, or node sizing, update those defaults before applying.

### 4. Connect `kubectl` to the new cluster

The default cluster name is `my-eks-cluster` and the default AWS region is
`ap-south-1`:

```powershell
aws eks update-kubeconfig --region ap-south-1 --name my-eks-cluster
kubectl get nodes
```

If you changed the Terraform defaults, use the resulting cluster name and
region instead.

### 5. Deploy and check the demo

Apply the combined Kubernetes manifest:

```powershell
kubectl apply -f kubernetes/complete-deploy.yaml
kubectl get pods
kubectl get services
kubectl wait --for=condition=available deployment --all --timeout=10m
```

Once the pods are ready, forward the frontend proxy to your machine:

```powershell
kubectl port-forward service/opentelemetry-demo-frontendproxy 8080:8080
```

Keep that command running and open <http://localhost:8080>. In a second
terminal, you can inspect application logs with:

```powershell
kubectl logs --all-containers=true --selector=app.kubernetes.io/instance=opentelemetry-demo
```

The combined Kubernetes manifest deploys the demo application, but it does not
set up an AWS Load Balancer Controller or the Compose observability backends.
The ALB ingress manifests need a compatible controller and your own host and
certificate configuration before use; `k8s-manifests-test/ingress.yml`
contains environment-specific domain and certificate values and should not be
applied as-is. For a basic application check, use the port-forward above.

### 6. Remove the AWS resources when finished

Delete the application first, then destroy the infrastructure:

```powershell
kubectl delete -f kubernetes/complete-deploy.yaml
terraform destroy
```

Review the Terraform destroy plan before confirming. The S3 state bucket is
managed separately in `backend/`; keep it if you plan to reuse the Terraform
configuration.

## Product Catalog CI/CD

The `product-catalog-ci` GitHub Actions workflow runs for pull requests to
`main` and can also be started with `workflow_dispatch`. It builds and tests
the Go service, runs golangci-lint, builds and pushes a container image, then
updates `kubernetes/productcatalog/deploy.yaml`. Configure the workflow's
`DOCKER_USERNAME`, `DOCKER_TOKEN`, and `TOKEN_GITHUB` secrets before running
the image-publishing jobs. The final workflow job pushes the manifest update
to `main`; review the workflow and repository branch protections before
enabling that behavior.
