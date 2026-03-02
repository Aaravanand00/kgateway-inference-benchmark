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

The runner scripts automatically ensure a deterministic environment by recreating or validating the kind cluster before executing benchmarks.

## 6. Running Benchmarks

### Baseline Benchmark
Evaluates pure HTTP routing without additional extensions or policies.
- **Windows**: `.\run-baseline.ps1`
- **Linux/macOS**: `chmod +x run-baseline.sh && ./run-baseline.sh`

### Inference Benchmark
Evaluates routing with an attached `TrafficPolicy` (the extension layer prototype).
- **Windows**: `.\run-inference.ps1`
- **Linux/macOS**: `chmod +x run-inference.sh && ./run-inference.sh`

Note: This prototype focuses on TrafficPolicy-based extension attachment. Model-aware routing, multi-backend inference selection, and advanced EPP configurations are considered future extensions of this framework.

## 7. What the Runner Scripts Do

Each runner script executes the following stages to ensure a clean and reproducible benchmark:

1. **Environment Setup**: Creates (or recreates) a `kind` cluster using the local configuration.
2. **Component Installation**: Installs `kgateway` and required Custom Resource Definitions (CRDs) via Helm.
3. **Backend Deployment**: Deploys the `inference-backend` (Go-based 100ms delay server).
4. **Routing Configuration**: Applies the `Gateway` and specific `HTTPRoute` resources.
5. **Extension Attachment**: Optionally attaches the `TrafficPolicy` (exclusive to the inference benchmark).
6. **Execution**: Initiates the `k6` load test against the gateway entrypoint.
7. **Persistence**: Stores the raw console output and metrics in the `results/` directory.

## 8. Results Summary
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

## 9. Reproducing Exact Numbers

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

## 10. Limitations
- **Local Environment**: High-percentile latency (p99) is subject to host system jitter and Docker Desktop resource scheduling.
- **Transport**: `kubectl port-forward` is used for simplicity but introduces overhead not present in production LoadBalancer environments.
- **Policy Scope**: The test utilizes a minimal extension policy; complex filters may increase processing time.

## 11. Streaming Inference Simulation
The benchmark now supports simulating streaming responses typical of Large Language Models (LLMs) to evaluate how gateway policies affect streaming performance.

### Endpoint: `/infer-stream`
The backend simulates a streaming response with the following behavior:
1. **Immediate Headers**: Sends HTTP status and headers immediately.
2. **Deterministic TTFT**: Waits 50ms before sending the first chunk.
3. **Token Streaming**: Sends 20 small JSON chunks, each separated by a 10ms delay.

### Metrics Definitions
- **TTFT (Time To First Token)**: The time from the initial request until the first byte of response data arrives. This is the most critical metric for interactive LLM applications.
- **ITL (Inter-Token Latency)**: The average time between receiving consecutive chunks (tokens). High ITL leads to "stuttering" in the UI.
- **Total Duration**: The total time from request start to the end of the stream.

> [!IMPORTANT]
> This suite uses a deterministic CPU-based simulator. GPU-based real LLM benchmarking (e.g., vLLM, Ollama) is planned for future milestones.

### Streaming Comparison Table (Placeholder)

| Metric | Direct Access | Gateway Path | Extension Path |
| :--- | :--- | :--- | :--- |
| **Median TTFT (p50)** | ~55 ms | TBD | TBD |
| **95th TTFT (p95)** | ~60 ms | TBD | TBD |
| **Avg ITL** | ~10 ms | TBD | TBD |
| **Total Duration** | ~250 ms | TBD | TBD |

Note: The Direct Access values shown above reflect expected deterministic simulator behavior (50ms TTFT + 10ms inter-token delay × 20 chunks) before gateway processing overhead. Gateway and Extension path values must be generated by running the streaming benchmark scripts locally.

## 12. Standard Service Comparison Mode
To isolate the latency added by the gateway vs the raw service, use the new direct comparison scripts:
- **Windows**: `.\run-direct.ps1`
- **Linux/macOS**: `./run-direct.sh`

These scripts measure three paths:
1. **Raw Service**: Direct `port-forward` to the backend pod (bypassing Envoy).
2. **Gateway Path**: Standard routing through kgateway.
3. **Extension Path**: Routing through kgateway with a TrafficPolicy (GatewayExtension IR) attached.

Results are summarized in `results/direct.txt`.

## 13. Future Work
- **Real Backend Integration**: Testing against vLLM or Ollama.
- **Streaming Policy Impact**: Measuring how rate-limiting or header-injection affects stream throughput.
## 14. Alignment with Upstream Issue #12289
This prototype addresses several foundational requirements outlined in kgateway Issue #12289 ("Inference: Publish Benchmark Tests"):

- Reproducible test environment using kind and deterministic scripts
- Direct comparison between raw Kubernetes Service and kgateway routing
- Extension-layer overhead measurement via TrafficPolicy attachment
- Simulated streaming inference metrics (TTFT, ITL, total duration)

The current implementation uses a CPU-based deterministic simulator to isolate gateway processing overhead. Integration with GPU-backed inference engines (e.g., vLLM, Ollama) and upstream inference-perf tooling is considered a future extension of this framework.

## 15. Repository Structure
```text
kgateway-inference-benchmark/
│   kind-config.yaml
│   Makefile
│   README.md
│   run-baseline.ps1
│   run-baseline.sh
│   run-inference.ps1
│   run-inference.sh
│   run-direct.ps1                   # NEW: Comparison runner
│   run-direct.sh                    # NEW: Comparison runner
│
├───backend/
│       main.go                      # Includes /infer-stream
│       ...
├───loadtest/
│       baseline.js
│       streaming.js                 # NEW: TTFT/Streaming test
│
└───results/
        baseline.txt
        inference.txt
        direct.txt                   # NEW: Comparison results
```

