# kgateway Inference Benchmark Prototype

## 1. Overview
This repository contains a performance benchmarking suite for [kgateway](https://kgateway.dev/). It evaluates the latency and throughput characteristics of the gateway when routing traffic to an inference-simulating backend, specifically comparing a baseline configuration against an extended configuration using the `TrafficPolicy` inference layer.

## 2. Benchmark Goal
The primary objective is to quantify the incremental performance overhead introduced by kgateway's extension mechanisms. By using a controlled backend with a fixed 100ms artificial delay, we can isolate the proxying and processing time added by the gateway's control and data plane.

## 3. Architecture Overview
The benchmark utilizes a standard Kubernetes Gateway API flow:
1. **Client**: [k6](https://k6.io/) load testing tool running on the host machine.
2. **Entrypoint**: `kubectl port-forward` mapping host port `8081` to the `minimal-gateway` service.
3. **Gateway**: `kgateway` (Envoy-based) implementing the Gateway API `HTTPRoute` and `TrafficPolicy`.
4. **Backend**: A minimal Go-based HTTP server (`inference-backend`) that introduces a persistent 100ms sleep before responding.

**Flow**: `k6` -> `localhost:8081` -> `kgateway` -> `inference-backend:8080`

## 4. Environment
- **Cluster**: `kind` (Kubernetes v1.31.0)
- **Runtime**: Docker Desktop (Windows/Linux/macOS)
- **Gateway**: kgateway v2.3.0-main
- **Standard**: Kubernetes Gateway API v1.2.0 (Standard Channel)

## 5. Quick Start

### Prerequisites
Ensure the following tools are installed and available in your `$PATH`:
- [Kind](https://kind.sigs.k8s.io/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/)
- [k6](https://k6.io/docs/get-started/installation/)
- [Docker](https://docs.docker.com/get-docker/)

### Initialization
All scripts are designed to be run from the repository root.

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
The benchmarks demonstrate that the attachment of a `TrafficPolicy` to an `HTTPRoute` in `kgateway v2.3.0-main` introduces negligible overhead relative to the baseline configuration. Throughput remains consistent, and median latency delta is under 1ms.

### Comparison Table

| Metric | Baseline (No Extension) | Inference (TrafficPolicy) | Delta |
| :--- | :--- | :--- | :--- |
| **Median Latency (p50)** | 107.76 ms | 107.48 ms | -0.28 ms |
| **95th Percentile (p95)** | 112.23 ms | 113.06 ms | +0.83 ms |
| **99th Percentile (p99)** | 117.71 ms | 123.94 ms | +6.23 ms |
| **Average Latency (avg)** | 108.13 ms | 108.08 ms | -0.05 ms |
| **Throughput (RPS)** | 461.29 req/s | 461.52 req/s | +0.23 req/s |
| **Error Rate** | 0% | 0% | 0 |

## 8. Limitations
- **Local Environment**: High-percentile latency (p99) is subject to host system jitter and Docker Desktop resource scheduling.
- **Transport**: `kubectl port-forward` is used for simplicity but introduces overhead not present in production LoadBalancer environments.
- **Policy Scope**: The test utilizes a minimal extension policy; complex filters may increase processing time.

## 9. Future Work
- **Real Backend Integration**: Testing against vLLM or Ollama to evaluate performance under heavy payload conditions.
- **Scaling Analysis**: Evaluating impact as the number of concurrent Virtual Users (VUs) increases beyond 50.
- **Cross-AZ Routing**: Measuring latency in multi-zone clusters.
