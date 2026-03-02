#!/bin/bash
# run-direct.sh
# Measures raw service latency vs gateway path vs extension latency

set -e

# 1. Ensure Kind cluster is up and backend is deployed
echo "[1/7] Ensuring Kind cluster is up..."
if ! kind get clusters | grep -q "^kgateway-bench$"; then
    ./run-baseline.sh || true
fi

# 2. Build and Load Backend Image (ensure latest with /infer-stream)
echo "[2/7] Updating backend image..."
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench

# 3. Ensure kgateway is installed with inference extension enabled
echo "[3/7] Ensuring kgateway is configured..."
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=true

# 4. Deploy Resources
echo "[4/7] Deploying resources..."
kubectl apply -f ./backend/
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/trafficpolicy.yaml

# Wait for readiness
kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s

# 5. Start Port-Forwards
echo "[5/7] Starting port-forwards..."
# Direct service access
kubectl port-forward svc/inference-backend 8080:80 > /dev/null 2>&1 &
PF_BACKEND=$!
# Gateway access
kubectl port-forward -n default svc/minimal-gateway 8081:80 > /dev/null 2>&1 &
PF_GATEWAY=$!

sleep 5

# 6. Run Comparisons
echo "Running Comparison Benchmarks..."
mkdir -p results
echo "Kgateway Inference Benchmark - Direct Comparison" > ./results/direct.txt
echo "Date: $(date)" >> ./results/direct.txt
echo "==========================================" >> ./results/direct.txt

echo -e "\n1. Raw Service Latency (Direct Port-Forward to Backend)" | tee -a ./results/direct.txt
TARGET_URL=http://localhost:8080/infer k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1 | grep -A 10 "http_req_duration" >> ./results/direct.txt

echo -e "\n2. Gateway Latency (Standard HTTPRoute)" | tee -a ./results/direct.txt
kubectl apply -f ./gateway/httproute-baseline.yaml
# Remove inference route if exists to avoid conflict
kubectl delete httproute inference-route --ignore-not-found
sleep 2
TARGET_URL=http://localhost:8081/infer k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1 | grep -A 10 "http_req_duration" >> ./results/direct.txt

echo -e "\n3. Extension Latency (Gateway + InferenceExtension)" | tee -a ./results/direct.txt
kubectl apply -f ./gateway/httproute-inference.yaml
# Baseline route might have same host/path, so we should be careful. 
# Usually they both target "/" if not specified.
kubectl delete httproute baseline-route --ignore-not-found
sleep 2
TARGET_URL=http://localhost:8081/infer k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1 | grep -A 10 "http_req_duration" >> ./results/direct.txt

# 7. Cleanup
echo "[7/7] Cleaning up..."
kill $PF_BACKEND $PF_GATEWAY
echo "Done. Results saved in results/direct.txt"
