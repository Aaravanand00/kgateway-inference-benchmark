# Makefile for kgateway Inference Benchmark

.PHONY: cluster install baseline inference clean

cluster:
	@echo "Ensuring Kind cluster is up..."
	@if kind get clusters | grep -q "^kgateway-bench$$"; then \
		echo "Warning: Cluster 'kgateway-bench' already exists. Recreating for clean benchmark..."; \
		kind delete cluster --name kgateway-bench; \
	fi
	kind create cluster --config kind-config.yaml --name kgateway-bench

install:
	@echo "Installing kgateway and backend..."
	kubectl create namespace kgateway-system --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds -n kgateway-system --version 2.3.0-main
	helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway -n kgateway-system --version 2.3.0-main --set kgateway.inferenceExtension.enabled=false
	docker build -t inference-backend:latest ./backend
	kind load docker-image inference-backend:latest --name kgateway-bench
	kubectl apply -f ./backend/

baseline:
	@echo "Applying baseline routing and running k6..."
	kubectl apply -f ./gateway/gateway.yaml
	kubectl apply -f ./gateway/httproute-baseline.yaml
	kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s
	@echo "Starting port-forward and benchmark..."
	# Background port-forwarding (works in Unix/WSL/Git Bash habitats)
	kubectl port-forward -n default svc/minimal-gateway 8081:80 > /dev/null 2>&1 & \
	PID=$$!; \
	sleep 5; \
	k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js | tee ./results/baseline.txt; \
	kill $$PID

inference:
	@echo "Applying inference routing and running k6..."
	kubectl apply -f ./gateway/gateway.yaml
	kubectl apply -f ./gateway/httproute-inference.yaml
	kubectl apply -f ./gateway/trafficpolicy.yaml
	kubectl wait --for=condition=Ready pod -l app=inference-backend --timeout=60s
	@echo "Starting port-forward and benchmark..."
	# Background port-forwarding (works in Unix/WSL/Git Bash habitats)
	kubectl port-forward -n default svc/minimal-gateway 8081:80 > /dev/null 2>&1 & \
	PID=$$!; \
	sleep 5; \
	k6 run --summary-trend-stats "avg,p(50),p(95),p(99)" ./loadtest/baseline.js | tee ./results/inference.txt; \
	kill $$PID

clean:
	@echo "Deleting Kind cluster..."
	kind delete cluster --name kgateway-bench
