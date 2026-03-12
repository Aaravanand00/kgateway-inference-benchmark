# run-agentgateway.ps1
# Benchmark for the kgateway -> agentgateway -> backend path.

# 1. Create Kind Cluster
Write-Host "[1/8] Ensuring Kind cluster is up..." -ForegroundColor Cyan
if (kind get clusters -q | Where-Object { $_ -eq "kgateway-bench" }) {
    Write-Warning "Cluster 'kgateway-bench' already exists. Recreating for clean benchmark environment..."
    kind delete cluster --name kgateway-bench
}
kind create cluster --config kind-config.yaml --name kgateway-bench

# Install Gateway API CRDs
Write-Host "Installing Gateway API CRDs..." -ForegroundColor Cyan
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# 2. Build and Load Images
Write-Host "[2/8] Building/Pulling and loading images..." -ForegroundColor Cyan
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench
docker pull ghcr.io/agentgateway/agentgateway:latest
kind load docker-image ghcr.io/agentgateway/agentgateway:latest --name kgateway-bench

# 3. Install kgateway and CRDs
Write-Host "[3/8] Installing kgateway CRDs and Helm Chart..." -ForegroundColor Cyan
kubectl create namespace kgateway-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds -n kgateway-system --version 2.3.0-main
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=false

# 4. Deploy Inference Backend
Write-Host "[4/8] Deploying inference backend..." -ForegroundColor Cyan
kubectl apply -f ./backend/

# 5. Deploy agentgateway
Write-Host "[5/8] Deploying agentgateway..." -ForegroundColor Cyan
kubectl apply -f ./agentgateway/config.yaml
kubectl apply -f ./agentgateway/deployment.yaml
kubectl apply -f ./agentgateway/service.yaml

# 6. Apply HTTPRoute for Agentgateway Path
Write-Host "[6/8] Applying httproute-agentgateway.yaml..." -ForegroundColor Cyan
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/httproute-agentgateway.yaml

# Wait for resources to be ready
Write-Host "Waiting for pods to be ready..." -ForegroundColor Cyan
kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s
kubectl wait --for=condition=Ready pod -l app=agentgateway --timeout=60s

# Wait for kgateway-managed Envoy pod to be ready
Write-Host "Waiting for minimal-gateway pod to be ready..." -ForegroundColor Cyan
while (!(kubectl get svc minimal-gateway -n default --no-headers 2>$null)) {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
}
kubectl wait --for=condition=Ready pod -l gateway.networking.k8s.io/gateway-name=minimal-gateway --timeout=60s

# 7. Start Port-Forward in Background
Write-Host "[7/8] Starting port-forward on localhost:8081..." -ForegroundColor Cyan
$pfProcess = Start-Process kubectl -ArgumentList "port-forward -n default svc/minimal-gateway 8081:80" -PassThru -NoNewWindow

# Verify port-forward is accepting connections
Write-Host "Verifying port-forward connectivity..." -ForegroundColor Cyan
$retryCount = 0
while ($retryCount -lt 15) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8081/infer" -Method Get -TimeoutSec 2
        if ($response) {
            Write-Host "Port-forwarding confirmed!" -ForegroundColor Green
            break
        }
    } catch {
        Write-Host "." -NoNewline
        $retryCount++
        Start-Sleep -Seconds 2
    }
}

# 8. Run k6 Load Test
Write-Host "[8/8] Running k6 benchmark (Agentgateway path)..." -ForegroundColor Cyan
k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js | Tee-Object -FilePath ./results/agentgateway.txt

# Cleanup
Write-Host "Cleaning up port-forward..." -ForegroundColor Cyan
Stop-Process -Id $pfProcess.Id -Force
Write-Host "Benchmark complete. Results saved in results/agentgateway.txt" -ForegroundColor Green
