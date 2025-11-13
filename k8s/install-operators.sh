#!/bin/bash
# Install required operators and ingress controller

set -e

echo "📦 Installing NGINX Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --wait

echo "📦 Installing CloudNativePG Operator..."
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm install cloudnative-pg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace \
  --wait

echo "✅ Operators installed successfully!"
echo ""
echo "Next steps:"
echo "1. Apply PostgreSQL cluster: kubectl apply -f k8s/postgres/cluster.yaml"
echo "2. Wait for cluster to be ready: kubectl wait --for=condition=Ready cluster/postgres-cluster --timeout=300s"
echo "3. Get database password: kubectl get secret postgres-cluster-superuser -o jsonpath='{.data.password}' | base64 -d"
echo "4. Update secret in k8s/mirror-api-chart/templates/secret.yaml with the password"
echo "5. Deploy app: helm install mirror-api ./k8s/mirror-api-chart"
