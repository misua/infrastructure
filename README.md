# DevOps Test Infrastructure - Complete Setup Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Initial Setup](#initial-setup)
4. [Terraform Infrastructure Deployment](#terraform-infrastructure-deployment)
5. [Kubernetes Configuration](#kubernetes-configuration)
6. [Database Setup](#database-setup)
7. [Application Deployment](#application-deployment)
8. [Azure DevOps Pipeline Setup](#azure-devops-pipeline-setup)
9. [Testing and Validation](#testing-and-validation)
10. [Troubleshooting](#troubleshooting)
11. [Cleanup](#cleanup)

---

## Prerequisites

You must have the following installed and configured:

- Azure subscription with active credits
- Azure CLI (`az --version` to verify)
- kubectl (`kubectl version --client` to verify)
- helm (`helm version` to verify)
- terraform (`terraform version` to verify)
- Docker (`docker --version` to verify)
- Git

Login to Azure:
```bash
az login
```

Set your subscription (if you have multiple):
```bash
az account list --output table
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

---

## Project Structure

```
infrastructure/
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # Main Terraform configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   └── modules/           # Terraform modules
│       ├── aks/           # AKS cluster
│       ├── acr/           # Container registry
│       ├── keyvault/      # Key vault
│       └── networking/    # VNet and subnets
└── k8s/                   # Kubernetes manifests
    ├── mirror-api-chart/  # Helm chart for application
    ├── postgres/          # PostgreSQL cluster
    └── install-operators.sh

mirror-api/
├── app/                   # Python application code
├── tests/                 # Unit tests
├── Dockerfile             # Container image definition
├── azure-pipelines.yml    # CI/CD pipeline
└── requirements.txt       # Python dependencies
```

---

## Initial Setup

### Update Terraform Variables

Before deploying, you must update these values to ensure uniqueness:

1. Edit `infrastructure/terraform/variables.tf`
2. Change the following default values:

```hcl
variable "acr_name" {
  default     = "mirrorapiregistry123"  # Change this - must be globally unique
}

variable "keyvault_name" {
  default     = "mirrorapikv123"  # Change this - must be globally unique
}
```

### Create Terraform State Storage

Terraform needs a storage account for state management. Create it manually:

```bash
# Create resource group for Terraform state (using Southeast Asia region - closest to Philippines)
az group create --name terraform-state-rg --location southeastasia

# Create storage account (name must be globally unique)
az storage account create \
  --name tfstatemirrorapi123 \
  --resource-group terraform-state-rg \
  --location southeastasia \
  --sku Standard_LRS

# Create container
az storage container create \
  --name tfstate \
  --account-name tfstatemirrorapi123
```

Update `infrastructure/terraform/main.tf` backend configuration with your storage account name:

```hcl
backend "azurerm" {
  resource_group_name  = "terraform-state-rg"
  storage_account_name = "tfstatemirrorapi123"  # Use your storage account name
  container_name       = "tfstate"
  key                  = "devops-test.tfstate"
}
```

---

## Terraform Infrastructure Deployment

### Step 1: Initialize Terraform

```bash
cd infrastructure/terraform
terraform init
```

Expected output: "Terraform has been successfully initialized"

### Step 2: Review Infrastructure Plan

```bash
terraform plan
```

Review the resources that will be created:
- Resource group
- Virtual network and subnet
- AKS cluster (2 nodes, Standard_B2s)
- Azure Container Registry (Basic tier)
- Key Vault
- Network security group

### Step 3: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

This takes approximately 15-20 minutes. Wait for completion.

### Step 4: Save Outputs

```bash
terraform output -json > ../outputs.json
```

Verify outputs:
```bash
terraform output
```

You should see:
- aks_cluster_name
- acr_login_server
- keyvault_uri
- resource_group_name

---

## Kubernetes Configuration

### Step 1: Get AKS Credentials

```bash
az aks get-credentials \
  --resource-group devops-test-rg \
  --name mirror-api-aks \
  --overwrite-existing
```

### Step 2: Verify Cluster Access

```bash
kubectl get nodes
```

Expected output: 2 nodes in "Ready" status

### Step 3: Install Required Operators

```bash
cd ../k8s
chmod +x install-operators.sh
./install-operators.sh
```

This installs:
- NGINX Ingress Controller
- CloudNativePG Operator

Wait for installation to complete (approximately 2-3 minutes).

### Step 4: Verify Operator Installation

```bash
# Check NGINX Ingress
kubectl get pods -n ingress-nginx

# Check CloudNativePG
kubectl get pods -n cnpg-system
```

All pods should be in "Running" status.

---

## Database Setup

### Step 1: Deploy PostgreSQL Cluster

```bash
kubectl apply -f postgres/cluster.yaml
```

### Step 2: Wait for Cluster Ready

```bash
kubectl wait --for=condition=Ready cluster/postgres-cluster --timeout=300s
```

This takes approximately 2-3 minutes.

### Step 3: Get Database Credentials

The CloudNativePG operator creates a secret named `postgres-cluster-app` (not `postgres-cluster-superuser`):

```bash
# Get username
kubectl get secret postgres-cluster-app -o jsonpath='{.data.username}' | base64 -d
echo

# Get password
kubectl get secret postgres-cluster-app -o jsonpath='{.data.password}' | base64 -d
echo
```

Copy the username and password. You will need them in the next step.

### Step 4: Create Application Database Secret

Replace `YOUR_PASSWORD_HERE` with the password from Step 3:

```bash
kubectl create secret generic mirror-api-secret \
  --from-literal=database-url="postgresql://postgres:YOUR_PASSWORD_HERE@postgres-cluster-rw:5432/mirrordb"
```

### Step 5: Verify Database

```bash
kubectl get pods
```

You should see `postgres-cluster-1` pod in "Running" status.

---

## Application Deployment

### Step 1: Build Docker Image Locally (Optional Test)

```bash
cd ../../mirror-api

# Build image
docker build -t mirror-api:test .

# Test locally
docker run -d -p 4004:4004 --name mirror-test mirror-api:test

# Test health endpoint
curl http://localhost:4004/api/health

# Stop and remove container
docker stop mirror-test
docker rm mirror-test
```

Expected response: `{"status":"ok"}`

### Step 2: Push Image to ACR

Get ACR login server from Terraform outputs:

```bash
cd ../infrastructure
ACR_SERVER=$(cat outputs.json | jq -r '.acr_login_server.value')
echo $ACR_SERVER
```

Login to ACR:

```bash
az acr login --name mirrorapiregistry123  # Use your ACR name
```

Tag and push image:

```bash
cd ../mirror-api
docker tag mirror-api:test ${ACR_SERVER}/mirror-api:latest
docker push ${ACR_SERVER}/mirror-api:latest
```

### Step 3: Update Helm Chart Values

Edit `infrastructure/k8s/mirror-api-chart/values.yaml`:

```yaml
image:
  repository: YOUR_ACR_SERVER/mirror-api  # Replace with your ACR server
  tag: latest
  pullPolicy: Always
```

### Step 4: Deploy Application with Helm

```bash
cd ../infrastructure/k8s
helm install mirror-api ./mirror-api-chart
```

### Step 5: Wait for Pods Ready

```bash
kubectl wait --for=condition=Ready pod -l app=mirror-api --timeout=300s
```

### Step 6: Verify Deployment

```bash
kubectl get pods -l app=mirror-api
```

You should see 2 pods in "Running" status with "2/2" ready.

---

## Azure DevOps Pipeline Setup

### Step 1: Create Azure DevOps Project

1. Go to https://dev.azure.com
2. Click "New Project"
3. Enter project name (e.g., "devops-test")
4. Click "Create"

### Step 2: Import Repository

1. Go to Repos > Files
2. Click "Import" at the bottom
3. Clone URL: Use your mirror-api repository path
4. Click "Import"

Alternatively, push to Azure Repos:

```bash
cd ../../mirror-api
git remote add azure https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_git/mirror-api
git push azure main
```

### Step 3: Create Service Connection

1. Go to Project Settings (bottom left)
2. Click "Service connections"
3. Click "New service connection"
4. Select "Docker Registry"
5. Select "Azure Container Registry"
6. Choose your subscription
7. Select your ACR (mirrorapiregistry123)
8. Service connection name: `ACR-ServiceConnection` (must match pipeline)
9. Click "Save"

### Step 4: Create Pipeline

1. Go to Pipelines
2. Click "New Pipeline"
3. Select "Azure Repos Git"
4. Select your mirror-api repository
5. Select "Existing Azure Pipelines YAML file"
6. Path: `/azure-pipelines.yml`
7. Click "Continue"
8. Click "Run"

### Step 5: Verify Pipeline Execution

The pipeline will:
- Run tests on all branches
- Build and push Docker image only on main branch
- Build stage only runs if tests pass

---

## Testing and Validation

### Step 1: Get Ingress IP Address

```bash
kubectl get ingress mirror-api
```

Wait until EXTERNAL-IP is assigned (may take 2-3 minutes).

Save the IP:

```bash
INGRESS_IP=$(kubectl get ingress mirror-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $INGRESS_IP
```

### Step 2: Test Health Endpoint

```bash
curl http://${INGRESS_IP}/api/health
```

Expected response: `{"status":"ok"}`

### Step 3: Test Mirror Endpoint

```bash
curl "http://${INGRESS_IP}/api/mirror?word=fOoBar25"
```

Expected response: `{"transformed":"52RAbOoF"}`

### Step 4: Test Additional Transformations

```bash
curl "http://${INGRESS_IP}/api/mirror?word=hello"
curl "http://${INGRESS_IP}/api/mirror?word=WORLD"
curl "http://${INGRESS_IP}/api/mirror?word=test@123"
```

### Step 5: Verify Database Persistence

```bash
kubectl exec -it postgres-cluster-1 -- psql -U postgres -d mirrordb -c "SELECT * FROM transformations;"
```

You should see all the word transformations saved.

### Step 6: Test CI/CD Pipeline

Create a test branch:

```bash
cd ../../mirror-api
git checkout -b test-pipeline
echo "# Test comment" >> app/main.py
git add -A
git commit -m "Test pipeline trigger"
git push origin test-pipeline
```

Go to Azure DevOps Pipelines and verify:
- Pipeline runs automatically
- Only "Test" stage executes
- "Build & Push" stage is skipped

Merge to main:

```bash
git checkout main
git merge test-pipeline
git push origin main
```

Verify:
- Pipeline runs automatically
- Both "Test" and "Build & Push" stages execute
- New image is pushed to ACR

### Step 7: Deploy Updated Image

```bash
cd ../infrastructure/k8s
helm upgrade mirror-api ./mirror-api-chart
kubectl rollout status deployment/mirror-api
```

---

## Troubleshooting

### Terraform Issues

**Error: Backend initialization required**
```bash
cd infrastructure/terraform
terraform init -reconfigure
```

**Error: Resource already exists**
```bash
terraform import <resource_type>.<resource_name> <azure_resource_id>
```

**Error: Insufficient quota**
- Check your Azure subscription limits
- Try a different region
- Reduce node count in variables.tf

### Kubernetes Issues

**Pods not starting**
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**Ingress not getting IP**
```bash
kubectl get svc -n ingress-nginx
kubectl describe ingress mirror-api
```

**Database connection errors**
```bash
# Verify secret exists
kubectl get secret mirror-api-secret -o yaml

# Check PostgreSQL logs
kubectl logs postgres-cluster-1
```

### Application Issues

**Health check failing**
```bash
# Check pod logs
kubectl logs -l app=mirror-api

# Exec into pod
kubectl exec -it <pod-name> -- /bin/bash
curl localhost:4004/api/health
```

**Database writes failing**
```bash
# Test database connection from pod
kubectl exec -it <pod-name> -- /bin/bash
apt-get update && apt-get install -y postgresql-client
psql $DATABASE_URL -c "SELECT 1;"
```

### Pipeline Issues

**Service connection error**
- Verify service connection name is exactly `ACR-ServiceConnection`
- Check service connection has permissions to ACR
- Re-create service connection if needed

**Tests failing**
```bash
# Run tests locally
cd mirror-api
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pytest -v
```

**Docker build failing**
- Check Dockerfile syntax
- Verify all files are committed to git
- Check Azure DevOps build logs for specific errors

---

## Cleanup

### Step 1: Delete Kubernetes Resources

```bash
cd infrastructure/k8s

# Delete application
helm uninstall mirror-api

# Delete PostgreSQL
kubectl delete -f postgres/cluster.yaml

# Delete operators
helm uninstall cloudnative-pg -n cnpg-system
helm uninstall ingress-nginx -n ingress-nginx

# Delete namespaces
kubectl delete namespace cnpg-system
kubectl delete namespace ingress-nginx
```

### Step 2: Destroy Terraform Infrastructure

```bash
cd ../terraform
terraform destroy
```

Type `yes` when prompted.

This takes approximately 10-15 minutes.

### Step 3: Delete Terraform State Storage (Optional)

```bash
az group delete --name terraform-state-rg --yes --no-wait
```

### Step 4: Verify Cleanup

```bash
az group list --output table
```

Ensure `devops-test-rg` and `terraform-state-rg` are deleted or being deleted.

---

## Additional Notes

### Cost Optimization

Current configuration uses minimal resources:
- AKS: 2 x Standard_B2s nodes (~$60/month)
- ACR: Basic tier (~$5/month)
- Storage: Minimal usage (~$1/month)
- Total estimated cost: ~$66/month

To reduce costs further:
- Use 1 node instead of 2 (edit terraform/variables.tf)
- Delete resources when not in use
- Use Azure free trial credits

### Security Considerations

This is a test environment. For production:
- Enable RBAC on AKS
- Use managed identities instead of admin credentials
- Store secrets in Key Vault, not Kubernetes secrets
- Enable network policies
- Use private endpoints for ACR
- Enable Azure Policy for compliance

### Scaling

To scale the application:

```bash
# Scale pods
kubectl scale deployment mirror-api --replicas=5

# Scale AKS nodes
az aks scale --resource-group devops-test-rg --name mirror-api-aks --node-count 3
```

### Monitoring

View logs:

```bash
# Application logs
kubectl logs -l app=mirror-api --tail=100 -f

# Database logs
kubectl logs postgres-cluster-1 --tail=100 -f

# Ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 -f
```

### Backup and Recovery

PostgreSQL backups (if configured):

```bash
# List backups
kubectl get backups

# Restore from backup
kubectl apply -f <backup-restore-manifest.yaml>
```
