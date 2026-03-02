# run-direct.ps1
# Measures raw service latency vs gateway path vs extension latency

$ErrorActionPreference = "Stop"

# 1. Ensure Kind cluster is up
Write-Host "[1/7] Ensuring Kind cluster is up..." -ForegroundColor Cyan
if (-not (kind get clusters -q | Where-Object { $_ -eq "kgateway-bench" })) {
    & ./run-baseline.ps1
}

# 2. Update Backend Image
Write-Host "[2/7] Updating backend image..." -ForegroundColor Cyan
docker build -t inference-backend:latest ./backend
kind load docker-image inference-backend:latest --name kgateway-bench

# 3. Configure kgateway
Write-Host "[3/7] Configuring kgateway..." -ForegroundColor Cyan
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=true

# 4. Deploy Resources
Write-Host "[4/7] Deploying resources..." -ForegroundColor Cyan
kubectl apply -f ./backend/
kubectl apply -f ./gateway/gateway.yaml
kubectl apply -f ./gateway/trafficpolicy.yaml

Write-Host "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s

# 5. Start Port-Forwards
Write-Host "[5/7] Starting port-forwards..." -ForegroundColor Cyan
$pfBackend = Start-Process kubectl -ArgumentList "port-forward svc/inference-backend 8080:80" -PassThru -NoNewWindow
$pfGateway = Start-Process kubectl -ArgumentList "port-forward -n default svc/minimal-gateway 8081:80" -PassThru -NoNewWindow

Start-Sleep -Seconds 5

# 6. Run Comparisons
Write-Host "Running Comparison Benchmarks..." -ForegroundColor Cyan
if (-not (Test-Path results)) { New-Item -ItemType Directory -Path results }

"Kgateway Inference Benchmark - Direct Comparison" | Out-File ./results/direct.txt
"Date: $(Get-Date)" | Add-Content ./results/direct.txt
"==========================================" | Add-Content ./results/direct.txt

Write-Host "`n1. Raw Service Latency (Direct Port-Forward to Backend)" -ForegroundColor Yellow
"1. Raw Service Latency (Direct Port-Forward to Backend)" | Add-Content ./results/direct.txt
$env:TARGET_URL = "http://localhost:8080/infer"
$out = k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1
$out | Select-String "http_req_duration" -Context 0,10 | Add-Content ./results/direct.txt

Write-Host "`n2. Gateway Latency (Standard HTTPRoute)" -ForegroundColor Yellow
"2. Gateway Latency (Standard HTTPRoute)" | Add-Content ./results/direct.txt
kubectl apply -f ./gateway/httproute-baseline.yaml
kubectl delete httproute inference-route --ignore-not-found
Start-Sleep -Seconds 2
$env:TARGET_URL = "http://localhost:8081/infer"
$out = k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1
$out | Select-String "http_req_duration" -Context 0,10 | Add-Content ./results/direct.txt

Write-Host "`n3. Extension Latency (Gateway + InferenceExtension)" -ForegroundColor Yellow
"3. Extension Latency (Gateway + InferenceExtension)" | Add-Content ./results/direct.txt
kubectl apply -f ./gateway/httproute-inference.yaml
kubectl delete httproute baseline-route --ignore-not-found
Start-Sleep -Seconds 2
$env:TARGET_URL = "http://localhost:8081/infer"
$out = k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js 2>&1
$out | Select-String "http_req_duration" -Context 0,10 | Add-Content ./results/direct.txt

# 7. Cleanup
Write-Host "[7/7] Cleaning up..." -ForegroundColor Cyan
Stop-Process -Id $pfBackend.Id -Force
Stop-Process -Id $pfGateway.Id -Force
Write-Host "Done. Results saved in results/direct.txt" -ForegroundColor Green
