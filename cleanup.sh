#!/bin/bash

# Cleanup Script for DevOps Test Infrastructure
# This script removes all resources created during the setup

set -e  # Exit on error

echo "=========================================="
echo "DevOps Test Infrastructure Cleanup"
echo "=========================================="
echo ""
echo "This will delete:"
echo "  - Kubernetes resources (Helm releases, PostgreSQL, operators)"
echo "  - Terraform infrastructure (AKS, ACR, Key Vault, networking)"
echo "  - Terraform state storage"
echo "  - Local Docker images"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "=========================================="
echo "Step 1: Cleaning up Kubernetes resources"
echo "=========================================="

# Check if kubectl is configured
if kubectl cluster-info &> /dev/null; then
    echo "✓ Connected to Kubernetes cluster"
    
    # Delete Helm releases
    echo "→ Deleting Helm release: mirror-api"
    helm uninstall mirror-api 2>/dev/null || echo "  (mirror-api not found, skipping)"
    
    # Delete PostgreSQL cluster
    echo "→ Deleting PostgreSQL cluster"
    kubectl delete -f k8s/postgres/cluster.yaml 2>/dev/null || echo "  (PostgreSQL cluster not found, skipping)"
    
    # Delete manually created secrets
    echo "→ Deleting manually created secrets"
    kubectl delete secret mirror-api-secret 2>/dev/null || echo "  (mirror-api-secret not found, skipping)"
    
    # Delete operators
    echo "→ Deleting CloudNativePG operator"
    helm uninstall cloudnative-pg -n cnpg-system 2>/dev/null || echo "  (CloudNativePG not found, skipping)"
    
    echo "→ Deleting NGINX Ingress Controller"
    helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || echo "  (NGINX Ingress not found, skipping)"
    
    # Delete namespaces
    echo "→ Deleting namespaces"
    kubectl delete namespace cnpg-system 2>/dev/null || echo "  (cnpg-system namespace not found, skipping)"
    kubectl delete namespace ingress-nginx 2>/dev/null || echo "  (ingress-nginx namespace not found, skipping)"
    
    echo "✓ Kubernetes resources cleaned up"
else
    echo "⚠ Not connected to Kubernetes cluster, skipping Kubernetes cleanup"
fi

echo ""
echo "=========================================="
echo "Step 2: Deleting ACR images"
echo "=========================================="

ACR_NAME="mirrorapiregistry123"

# Check if ACR exists
if az acr show --name $ACR_NAME &> /dev/null; then
    echo "→ Deleting all images from ACR: $ACR_NAME"
    
    # List and delete all repositories
    REPOS=$(az acr repository list --name $ACR_NAME --output tsv 2>/dev/null || echo "")
    
    if [ -n "$REPOS" ]; then
        for repo in $REPOS; do
            echo "  → Deleting repository: $repo"
            az acr repository delete --name $ACR_NAME --repository $repo --yes 2>/dev/null || echo "    (failed to delete $repo)"
        done
        echo "✓ ACR images deleted"
    else
        echo "  (no repositories found in ACR)"
    fi
else
    echo "⚠ ACR not found, skipping ACR cleanup"
fi

echo ""
echo "=========================================="
echo "Step 3: Destroying Terraform infrastructure"
echo "=========================================="

cd terraform

if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
    echo "→ Running terraform destroy"
    terraform destroy -auto-approve
    echo "✓ Terraform infrastructure destroyed"
else
    echo "⚠ No Terraform state found, skipping Terraform destroy"
fi

cd ..

echo ""
echo "=========================================="
echo "Step 4: Deleting Terraform state storage"
echo "=========================================="

STATE_RG="terraform-state-rg"

if az group show --name $STATE_RG &> /dev/null; then
    echo "→ Deleting resource group: $STATE_RG"
    az group delete --name $STATE_RG --yes --no-wait
    echo "✓ Terraform state storage deletion initiated (running in background)"
else
    echo "⚠ Terraform state resource group not found, skipping"
fi

echo ""
echo "=========================================="
echo "Step 5: Cleaning up local Docker images"
echo "=========================================="

echo "→ Removing local Docker images"

# Remove mirror-api images
docker rmi mirror-api:test 2>/dev/null || echo "  (mirror-api:test not found)"
docker rmi mirrorapiregistry123.azurecr.io/mirror-api:latest 2>/dev/null || echo "  (ACR mirror-api:latest not found)"

# Remove dangling images
echo "→ Removing dangling images"
docker image prune -f

echo "✓ Local Docker images cleaned up"

echo ""
echo "=========================================="
echo "Step 6: Cleaning up local files"
echo "=========================================="

echo "→ Removing outputs.json"
rm -f outputs.json

echo "→ Removing Terraform state files"
rm -f terraform/terraform.tfstate*
rm -f terraform/.terraform.lock.hcl
rm -rf terraform/.terraform

echo "✓ Local files cleaned up"

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Kubernetes resources deleted"
echo "  ✓ ACR images deleted"
echo "  ✓ Terraform infrastructure destroyed"
echo "  ✓ Terraform state storage deletion initiated"
echo "  ✓ Local Docker images removed"
echo "  ✓ Local files cleaned up"
echo ""
echo "Note: Resource group deletion runs in the background."
echo "Verify completion with: az group list --output table"
echo ""
echo "To verify all resources are deleted:"
echo "  az group list --output table"
echo "  kubectl get all --all-namespaces"
echo "  docker images"
