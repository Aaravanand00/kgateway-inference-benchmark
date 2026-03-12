#!/bin/bash
# run-direct.sh
# Direct comparison: raw service latency vs. gateway path vs. extension path.

set -e

# 1. Ensure Kind cluster is up and backend is deployed
echo "[1/7] Ensuring Kind cluster is up..."
if ! kind get clusters | grep -q "^kgateway-bench$"; then
    ./scripts/run-baseline.sh || true
fi

# 2. Update backend image (ensure /infer-stream endpoint is present)
echo "[2/7] Updating backend image..."
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench

# 3. Configure kgateway with inference extension enabled
echo "[3/7] Configuring kgateway..."
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=true

# 4. Deploy Resources
echo "[4/7] Deploying resources..."
kubectl apply -f ./backend/
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/trafficpolicy.yaml

kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s

# 5. Start Port-Forwards
echo "[5/7] Starting port-forwards..."
kubectl port-forward svc/inference-backend 8080:80 > /dev/null 2>&1 &
PF_BACKEND=$!
kubectl port-forward -n default svc/minimal-gateway 8081:80 > /dev/null 2>&1 &
PF_GATEWAY=$!

sleep 5

# 6. Run Comparisons
echo "Running comparison benchmarks..."
mkdir -p results
echo "kgateway Inference Benchmark - Direct Comparison" > ./results/direct.txt
echo "Date: $(date)" >> ./results/direct.txt
echo "==========================================" >> ./results/direct.txt

echo -e "\n1. Raw Service Latency (Direct Port-Forward to Backend)" | tee -a ./results/direct.txt
TARGET_URL=http://localhost:8080/infer k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1 | grep -A 10 "http_req_duration" >> ./results/direct.txt

echo -e "\n2. Gateway Latency (Standard HTTPRoute)" | tee -a ./results/direct.txt
kubectl apply -f ./gateway/httproute-baseline.yaml
kubectl delete httproute inference-route --ignore-not-found
sleep 2
TARGET_URL=http://localhost:8081/infer k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1 | grep -A 10 "http_req_duration" >> ./results/direct.txt

echo -e "\n3. Extension Latency (Gateway + InferenceExtension)" | tee -a ./results/direct.txt
kubectl apply -f ./gateway/httproute-inference.yaml
kubectl delete httproute baseline-route --ignore-not-found
sleep 2
TARGET_URL=http://localhost:8081/infer k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1 | grep -A 10 "http_req_duration" >> ./results/direct.txt

# 7. Cleanup
echo "[7/7] Cleaning up..."
kill $PF_BACKEND $PF_GATEWAY
echo "Done. Results saved in results/direct.txt"
