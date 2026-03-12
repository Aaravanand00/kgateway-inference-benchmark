#!/bin/bash
# run-agentgateway.sh
# Benchmark for the kgateway -> agentgateway -> backend path.

set -e

# 1. Create Kind Cluster
echo "[1/8] Ensuring Kind cluster is up..."
if kind get clusters | grep -q "^kgateway-bench$"; then
    echo "Warning: Cluster 'kgateway-bench' already exists. Recreating for clean benchmark..."
    kind delete cluster --name kgateway-bench
fi
kind create cluster --config kind-config.yaml --name kgateway-bench

# Install Gateway API CRDs
echo "Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# 2. Build and Load Images
echo "[2/8] Building/Pulling and loading images..."
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench
docker pull ghcr.io/agentgateway/agentgateway:latest
kind load docker-image ghcr.io/agentgateway/agentgateway:latest --name kgateway-bench

# 3. Install kgateway and CRDs
echo "[3/8] Installing kgateway CRDs and Helm Chart..."
kubectl create namespace kgateway-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds -n kgateway-system --version 2.3.0-main
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=false

# 4. Deploy Inference Backend
echo "[4/8] Deploying inference backend..."
kubectl apply -f ./backend/

# 5. Deploy agentgateway
echo "[5/8] Deploying agentgateway..."
kubectl apply -f ./agentgateway/config.yaml
kubectl apply -f ./agentgateway/deployment.yaml
kubectl apply -f ./agentgateway/service.yaml

# 6. Apply HTTPRoute for Agentgateway Path
echo "[6/8] Applying httproute-agentgateway.yaml..."
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/httproute-agentgateway.yaml

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s
kubectl wait --for=condition=Ready pod -l app=agentgateway --timeout=60s

# Wait for kgateway-managed Envoy pod to be ready
echo "Waiting for minimal-gateway pod to be ready..."
until kubectl get svc minimal-gateway -n default > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
kubectl wait --for=condition=Ready pod -l gateway.networking.k8s.io/gateway-name=minimal-gateway --timeout=60s

# 7. Start Port-Forward in Background
echo "[7/8] Starting port-forward on localhost:8081..."
kubectl port-forward -n default svc/minimal-gateway 8081:80 > /dev/null 2>&1 &
PF_PID=$!

# Verify port-forward is accepting connections
echo "Verifying port-forward connectivity..."
for i in {1..10}; do
    if curl -s http://localhost:8081/infer > /dev/null; then
        echo "Port-forwarding confirmed!"
        break
    fi
    echo -n "."
    sleep 2
done

# 8. Run k6 Load Test
echo "[8/8] Running k6 benchmark (Agentgateway path)..."
k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js | tee ./results/agentgateway.txt

# Cleanup
echo "Cleaning up port-forward..."
kill $PF_PID
echo "Benchmark complete. Results saved in results/agentgateway.txt"
