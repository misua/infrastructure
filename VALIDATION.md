# Phase 6: End-to-End Validation Checklist

## Prerequisites
- Azure subscription with free trial credits
- Azure CLI installed and logged in (`az login`)
- kubectl installed
- helm installed
- terraform installed

## Step 1: Terraform Infrastructure Deployment

```bash
cd terraform

# Initialize Terraform (first time only)
terraform init

# Review what will be created
terraform plan

# Create infrastructure (takes ~15-20 minutes)
terraform apply

# Save outputs for later
terraform output -json > ../outputs.json
```

**Validation:**
- [ ] `terraform apply` completes without errors
- [ ] AKS cluster is created
- [ ] ACR is created
- [ ] KeyVault is created

## Step 2: Configure kubectl

```bash
# Get AKS credentials
az aks get-credentials --resource-group devops-test-rg --name mirror-api-aks

# Verify connection
kubectl get nodes
```

**Validation:**
- [ ] kubectl connects to cluster
- [ ] 2 nodes are in "Ready" state

## Step 3: Install Operators

```bash
cd ../k8s
./install-operators.sh
```

**Validation:**
- [ ] NGINX Ingress Controller pods are running
- [ ] CloudNativePG operator pods are running

## Step 4: Deploy PostgreSQL

```bash
# Create PostgreSQL cluster
kubectl apply -f postgres/cluster.yaml

# Wait for cluster to be ready (takes ~2-3 minutes)
kubectl wait --for=condition=Ready cluster/postgres-cluster --timeout=300s

# Get database password
DB_PASSWORD=$(kubectl get secret postgres-cluster-superuser -o jsonpath='{.data.password}' | base64 -d)
echo "Database password: $DB_PASSWORD"
```

**Validation:**
- [ ] PostgreSQL pod is running
- [ ] Database password retrieved successfully

## Step 5: Update Application Secret

```bash
# Update the secret with real database password
kubectl create secret generic mirror-api-secret \
  --from-literal=database-url="postgresql://postgres:${DB_PASSWORD}@postgres-cluster-rw:5432/mirrordb" \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Validation:**
- [ ] Secret updated with database connection string

## Step 6: Build and Push Docker Image (Local Test)

```bash
cd ../../mirror-api

# Build Docker image
docker build -t mirror-api:test .

# Test locally (without database)
docker run -p 4004:4004 mirror-api:test

# In another terminal, test health endpoint
curl http://localhost:4004/api/health
# Should return: {"status":"ok"}

# Stop the container
docker stop $(docker ps -q --filter ancestor=mirror-api:test)
```

**Validation:**
- [ ] Docker image builds successfully
- [ ] Health endpoint returns `{"status":"ok"}`

## Step 7: Push to ACR

```bash
# Get ACR login server from Terraform outputs
ACR_SERVER=$(cat ../infrastructure/outputs.json | jq -r '.acr_login_server.value')

# Login to ACR
az acr login --name mirrorapiregistry  # Use your ACR name

# Tag and push
docker tag mirror-api:test ${ACR_SERVER}/mirror-api:latest
docker push ${ACR_SERVER}/mirror-api:latest
```

**Validation:**
- [ ] Image pushed to ACR successfully

## Step 8: Deploy Application with Helm

```bash
cd ../infrastructure/k8s

# Update values.yaml with your ACR name first!
# Then deploy
helm install mirror-api ./mirror-api-chart

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod -l app=mirror-api --timeout=300s
```

**Validation:**
- [ ] Helm install succeeds
- [ ] 2 mirror-api pods are running
- [ ] Pods pass readiness checks

## Step 9: Test Ingress

```bash
# Get Ingress IP (may take a few minutes to assign)
kubectl get ingress mirror-api

# Wait for EXTERNAL-IP to appear, then test
INGRESS_IP=$(kubectl get ingress mirror-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test health endpoint
curl http://${INGRESS_IP}/api/health

# Test mirror endpoint
curl "http://${INGRESS_IP}/api/mirror?word=fOoBar25"
# Should return: {"transformed":"52RAbOoF"}
```

**Validation:**
- [ ] Ingress has external IP assigned
- [ ] `/api/health` returns `{"status":"ok"}`
- [ ] `/api/mirror?word=fOoBar25` returns `{"transformed":"52RAbOoF"}`

## Step 10: Verify Database Persistence

```bash
# Make a few requests
curl "http://${INGRESS_IP}/api/mirror?word=test"
curl "http://${INGRESS_IP}/api/mirror?word=hello"

# Check database
kubectl exec -it postgres-cluster-1 -- psql -U postgres -d mirrordb -c "SELECT * FROM transformations;"
```

**Validation:**
- [ ] Transformations are saved in database
- [ ] Data persists across pod restarts

## Step 11: Azure DevOps Pipeline Setup

1. Go to Azure DevOps (dev.azure.com)
2. Create new project or use existing
3. Go to Repos → Import repository → Use mirror-api git repo
4. Go to Pipelines → Create Pipeline → Azure Repos Git → Select mirror-api repo
5. Pipeline will auto-detect `azure-pipelines.yml`
6. Before running, create Service Connection:
   - Project Settings → Service connections → New service connection
   - Choose "Docker Registry"
   - Select "Azure Container Registry"
   - Choose your ACR
   - Name it "ACR-ServiceConnection" (must match pipeline)

**Validation:**
- [ ] Pipeline created successfully
- [ ] Service connection configured

## Step 12: Test CI/CD Pipeline

```bash
# Create a feature branch
cd ../../mirror-api
git checkout -b test-pipeline

# Make a small change (add a comment)
echo "# Test change" >> app/main.py

# Commit and push
git add -A
git commit -m "Test pipeline"
git push origin test-pipeline
```

**In Azure DevOps:**
- Watch pipeline run
- Verify only "Test" stage runs (not Build & Push)

**Validation:**
- [ ] Pipeline triggers on branch push
- [ ] Tests run and pass
- [ ] Build stage is skipped (not on main branch)

## Step 13: Test Main Branch Pipeline

```bash
# Merge to main
git checkout main
git merge test-pipeline
git push origin main
```

**In Azure DevOps:**
- Watch pipeline run
- Verify both "Test" and "Build & Push" stages run

**Validation:**
- [ ] Pipeline triggers on main branch push
- [ ] Tests run and pass
- [ ] Docker image builds
- [ ] Image pushed to ACR with commit SHA and `latest` tags

## Step 14: Deploy Updated Image

```bash
cd ../infrastructure/k8s

# Upgrade Helm release to pull latest image
helm upgrade mirror-api ./mirror-api-chart

# Verify new pods are running
kubectl get pods -l app=mirror-api
```

**Validation:**
- [ ] Helm upgrade succeeds
- [ ] New pods are running with updated image
- [ ] Application still responds correctly

## Final Validation Summary

✅ **All checks passed** - System is fully operational!

- Infrastructure provisioned via Terraform
- AKS cluster running
- PostgreSQL database operational
- Application deployed and accessible
- Ingress routing traffic correctly
- Database persistence working
- CI/CD pipeline functional
- Tests passing before builds
- Docker images building and pushing to ACR

## Cleanup (When Done)

```bash
# Delete Helm releases
helm uninstall mirror-api
helm uninstall cloudnative-pg -n cnpg-system
helm uninstall ingress-nginx -n ingress-nginx

# Destroy infrastructure
cd ../../infrastructure/terraform
terraform destroy

# Delete resource groups (if any remain)
az group delete --name devops-test-rg --yes --no-wait
```
