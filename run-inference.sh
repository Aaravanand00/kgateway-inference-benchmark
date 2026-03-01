#!/bin/bash
# run-inference.sh
# Reproducible inference benchmark for kgateway (using TrafficPolicy extension)

set -e

# 1. Create Kind Cluster
echo "[1/7] Ensuring Kind cluster is up..."
if kind get clusters | grep -q "^kgateway-bench$"; then
    echo "Warning: Cluster 'kgateway-bench' already exists. Recreating for clean benchmark..."
    kind delete cluster --name kgateway-bench
fi
kind create cluster --config kind-config.yaml --name kgateway-bench

# 2. Build and Load Backend Image
echo "[2/7] Building and loading backend image..."
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench

# 3. Install kgateway and CRDs
echo "[3/7] Installing kgateway CRDs and Helm Chart..."
kubectl create namespace kgateway-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds -n kgateway-system --version 2.3.0-main
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=false

# 4. Deploy Inference Resources
echo "[4/7] Deploying backend and inference extension policy..."
kubectl apply -f ./backend/
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/httproute-inference.yaml
kubectl apply -f ./gateway/trafficpolicy.yaml

# Wait for resources to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s

# 5. Start Port-Forward in Background
echo "[5/7] Starting port-forward on localhost:8081..."
kubectl port-forward -n default svc/minimal-gateway 8081:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 5 # Wait for PF to establish

# 6. Run k6 Load Test
echo "[6/7] Running k6 benchmark..."
k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js | tee ./results/inference.txt

# 7. Cleanup
echo "[7/7] Cleaning up port-forward..."
kill $PF_PID
echo "Benchmark complete. Results saved in results/inference.txt"
