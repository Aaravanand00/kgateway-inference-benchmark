# run-inference.ps1
# Reproducible inference benchmark for kgateway (using TrafficPolicy extension)

# 1. Create Kind Cluster
Write-Host "[1/7] Ensuring Kind cluster is up..." -ForegroundColor Cyan
if (kind get clusters -q | Where-Object { $_ -eq "kgateway-bench" }) {
    Write-Warning "Cluster 'kgateway-bench' already exists. Recreating for a clean benchmark environment..."
    kind delete cluster --name kgateway-bench
}
kind create cluster --config kind-config.yaml --name kgateway-bench

# 2. Build and Load Backend Image
Write-Host "[2/7] Building and loading backend image..." -ForegroundColor Cyan
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench

# 3. Install kgateway and CRDs
Write-Host "[3/7] Installing kgateway CRDs and Helm Chart..." -ForegroundColor Cyan
kubectl create namespace kgateway-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds -n kgateway-system --version 2.3.0-main
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=false

# 4. Deploy Inference Resources
Write-Host "[4/7] Deploying backend and inference extension policy..." -ForegroundColor Cyan
kubectl apply -f ./backend/
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/httproute-inference.yaml
kubectl apply -f ./gateway/trafficpolicy.yaml

# Wait for resources to be ready
Write-Host "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s

# 5. Start Port-Forward in Background
Write-Host "[5/7] Starting port-forward on localhost:8081..." -ForegroundColor Cyan
$pfProcess = Start-Process kubectl -ArgumentList "port-forward -n default svc/minimal-gateway 8081:80" -PassThru -NoNewWindow
Start-Sleep -Seconds 5 # Wait for PF to establish

# 6. Run k6 Load Test
Write-Host "[6/7] Running k6 benchmark..." -ForegroundColor Cyan
# Assumes 'k6' is in your system PATH
k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js | Tee-Object -FilePath ./results/inference.txt

# 7. Cleanup
Write-Host "[7/7] Cleaning up port-forward..." -ForegroundColor Cyan
Stop-Process -Id $pfProcess.Id -Force
Write-Host "Benchmark complete. Results saved in results/inference.txt" -ForegroundColor Green
