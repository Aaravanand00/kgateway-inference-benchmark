# kgateway Inference Benchmark Prototype

This prototype validates the feasibility of a reproducible benchmarking framework for kgateway inference routing extensions.

## 1. Overview
This repository contains a performance benchmarking suite for [kgateway](https://kgateway.dev/). It evaluates the latency and throughput characteristics of the gateway when routing traffic to an inference-simulating backend, specifically comparing a baseline configuration against an extended configuration using the `TrafficPolicy` inference layer.

## 2. Benchmark Goal
The primary objective is to quantify the incremental performance overhead introduced by kgateway's extension mechanisms. By using a controlled backend with a fixed 100ms artificial delay, we can isolate the proxying and processing time added by the gateway's control and data plane.

## 3. Architecture Overview

### ASCII Diagram
```text
  Client (k6)
      ↓
kubectl port-forward (localhost:8081)
      ↓
  kgateway (Gateway API)
      ↓
inference-backend (100ms delay)
```

The benchmark utilizes a standard Kubernetes Gateway API flow:
1. **Client**: [k6](https://k6.io/) load testing tool running on the host machine.
2. **Entrypoint**: `kubectl port-forward` mapping host port `8081` to the `minimal-gateway` service.
3. **Gateway**: `kgateway` (Envoy-based) implementing the Gateway API `HTTPRoute` and `TrafficPolicy`.
4. **Backend**: A minimal Go-based HTTP server (`inference-backend`) that introduces a persistent 100ms sleep before responding.

## 4. Environment

### Tested On
- **OS**: Windows 11 / macOS / Linux
- **Runtime**: Docker Desktop (Windows) / Docker Engine
- **Hardware**: 8 CPU / 16GB RAM host (recommended)
- **Tools**:
    - `kind` v0.23+
    - Kubernetes v1.31.0
    - kgateway v2.3.0-main
    - Kubernetes Gateway API v1.2.0 (Standard Channel)

## 5. Quick Start

### Prerequisites
Ensure the following tools are installed and available in your `$PATH`:
- [Kind](https://kind.sigs.k8s.io/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/)
- [k6](https://k6.io/docs/get-started/installation/)
- [Docker](https://docs.docker.com/get-docker/)

### Initialization
All scripts are designed to be run from the repository root. Ensure you have a clean environment or use the provided scripts to recreate the cluster.

## 6. Running Benchmarks

### Baseline Benchmark
Evaluates pure HTTP routing without additional extensions or policies.
- **Windows**: `.\run-baseline.ps1`
- **Linux/macOS**: `chmod +x run-baseline.sh && ./run-baseline.sh`

### Inference Benchmark
Evaluates routing with an attached `TrafficPolicy` (the extension layer prototype).
- **Windows**: `.\run-inference.ps1`
- **Linux/macOS**: `chmod +x run-inference.sh && ./run-inference.sh`

## 7. Results Summary
The benchmarks demonstrate that the attachment of a `TrafficPolicy` to an `HTTPRoute` in `kgateway v2.3.0-main` introduces negligible overhead relative to the baseline configuration. Throughput remains consistent, and median latency delta is typically within expected variance margins.

### Comparison Table

| Metric | Baseline (No Extension) | Inference (TrafficPolicy) | Delta |
| :--- | :--- | :--- | :--- |
| **Median Latency (p50)** | 107.76 ms | 107.48 ms | -0.28 ms |
| **95th Percentile (p95)** | 112.23 ms | 113.06 ms | +0.83 ms |
| **99th Percentile (p99)** | 117.71 ms | 123.94 ms | +6.23 ms |
| **Average Latency (avg)** | 108.13 ms | 108.08 ms | -0.05 ms |
| **Throughput (RPS)** | 461.29 req/s | 461.52 req/s | +0.23 req/s |
| **Error Rate** | 0% | 0% | 0 |

## 8. Reproducing Exact Numbers

When running the benchmarks, the `k6` output will follow this pattern:

```text
     http_req_duration..............: avg=108.xxms p(50)=107.xxms p(95)=113.xxms p(99)=123.xxms
     http_req_failed................: 0.00%  ✓ 0          ✗ 27742
     http_reqs......................: 27742  461.519198/s
```

### Expected Approximate Ranges
- **Avg/p50**: ~105ms - 110ms (reflects 100ms backend + ~5-10ms proxy/network overhead)
- **RPS**: ~450 - 470 req/s (at 50 Virtual Users)
- **Errors**: Should consistently be 0.00%.

## 9. Limitations
- **Local Environment**: High-percentile latency (p99) is subject to host system jitter and Docker Desktop resource scheduling.
- **Transport**: `kubectl port-forward` is used for simplicity but introduces overhead not present in production LoadBalancer environments.
- **Policy Scope**: The test utilizes a minimal extension policy; complex filters may increase processing time.

## 10. Future Work
- **Real Backend Integration**: Testing against vLLM or Ollama to evaluate performance under heavy payload conditions.
- **Scaling Analysis**: Evaluating impact as the number of concurrent Virtual Users (VUs) increases beyond 50.
- **Cross-AZ Routing**: Measuring latency in multi-zone clusters.

## 11. Repository Structure
```text
kgateway-inference-benchmark/
│   kind-config.yaml
│   Makefile
│   README.md                        # Project documentation
│   run-baseline.ps1                 # Windows baseline runner
│   run-baseline.sh                  # Linux baseline runner
│   run-inference.ps1                # Windows inference runner
│   run-inference.sh                 # Linux inference runner
│   .gitignore
│
├───backend/                         # Inference simulator
│       deployment.yaml
│       Dockerfile
│       main.go
│       service.yaml
│
├───gateway/                         # Gateway API resources
│       gateway.yaml
│       httproute-baseline.yaml       # Original baseline route
│       httproute-inference.yaml      # Prototype inference route
│       trafficpolicy.yaml            # Extension policy layer
│
├───loadtest/                        # k6 scripts
│       baseline.js
│
└───results/                         # Benchmark data
        baseline.txt                 # Baseline run logs
        inference.txt                # Inference run logs
        comparison.md                # Comparison table & Analysis
```
