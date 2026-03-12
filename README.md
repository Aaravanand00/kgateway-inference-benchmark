# kgateway Inference Benchmark

A reproducible benchmarking framework to measure the performance impact of kgateway's AI inference data plane extensions.

## 1. Overview

This repository benchmarks the overhead introduced by each layer of the inference routing stack:

- **Gateway routing**: Standard HTTP routing through kgateway (Envoy).
- **TrafficPolicy inference extensions**: Overhead of kgateway's specialized inference data plane.
- **agentgateway data plane**: Latency impact of the agentgateway (Rust-based) proxy in the inference path.

By using a controlled backend with a fixed 100ms artificial delay, we isolate the processing time added by each infrastructure layer.

## 2. System Architecture

```text
Client (k6)
   ↓
kgateway (Envoy proxy)
   ↓
agentgateway (Rust AI data plane)
   ↓
Inference backend (100ms delay simulator)
```

### Component Details

- **Client (k6)**: High-performance load generator configured to simulate concurrent AI inference requests.
- **Entrypoint**: `kubectl port-forward` mapping host port `8081` into the cluster gateway.
- **kgateway (Envoy)**: Cloud-native API gateway implementing the Gateway API and kgateway AI extensions.
- **agentgateway**: Rust-based data plane component providing specialized inference request processing.
- **Inference Backend**: Deterministic Go-based simulator introducing a fixed 100ms processing delay.

### Architectural Flow

```text
Client
   ↓
Load Generator (k6)
   ↓
kgateway (Envoy)
   ↓
TrafficPolicy / Extension Layer
   ↓
agentgateway
   ↓
Inference Backend
```

## 3. Benchmark Methodology

Key metrics collected during each run:

- **TTFT (Time To First Token)**: Latency until the first byte of a response stream is received.
- **ITL (Inter-Token Latency)**: Average duration between streaming chunks, identifying potential stutter in model responses.
- **Request Latency (p50/p95/p99)**: Percentile analysis to identify tail latency issues.
- **Throughput (RPS)**: Maximum sustainable request volume before significant degradation.

### Benchmark Modes

```text
Direct Mode:       Client ──────────────────────────────────────────→ Service
Baseline Mode:     Client ─────────→ kgateway ───────────────────────→ Backend
Inference Mode:    Client ─────────→ kgateway (TrafficPolicy) ───────→ Backend
Agentgateway Mode: Client ─────────→ kgateway ───────→ agentgateway ──→ Backend
```

## 4. Benchmark Pipeline

Automated lifecycle of a single benchmark run (as implemented in `scripts/`):

```text
[ Provisioning ]       [ Deployment ]        [ Execution ]        [ Persistence ]
  Kind Cluster          kgateway/Helm         k6 Load Test         Results Disk
       │                     │                     │                    │
       ▼                     ▼                     ▼                    ▼
   Recreate CLI ────────► Load Images ────────► Run k6 Test ────────► Save .txt
   & K8s context         & Apply Yaml         & Port-Forward        & comparison
```

## 5. Environment

### Tested On

- **OS**: Windows 11 / macOS / Linux
- **Runtime**: Docker Desktop (Windows) / Docker Engine
- **Hardware**: 8 CPU / 16GB RAM host (recommended)
- **Tools**:
    - `kind` v0.23+
    - Kubernetes v1.31.0
    - kgateway v2.3.0 (main branch build)
    - Kubernetes Gateway API v1.2.0 (Standard Channel)

## 6. Quick Start

### Prerequisites

Ensure the following tools are installed and available in your `$PATH`:

- [Kind](https://kind.sigs.k8s.io/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/)
- [k6](https://k6.io/docs/get-started/installation/)
- [Docker](https://docs.docker.com/get-docker/)

### Initialization

All scripts are designed to be run from the repository root. The runner scripts automatically recreate or validate the kind cluster before executing benchmarks, ensuring a deterministic environment.

## 7. Running Benchmarks

### Baseline Benchmark

Evaluates pure HTTP routing without additional extensions or policies.

- **Windows**: `.\scripts\run-baseline.ps1`
- **Linux/macOS**: `./scripts/run-baseline.sh`

### Inference Benchmark

Evaluates routing with an attached `TrafficPolicy` (the extension layer prototype).

- **Windows**: `.\scripts\run-inference.ps1`
- **Linux/macOS**: `./scripts/run-inference.sh`

### Agentgateway Benchmark

Evaluates the overhead of the agentgateway data plane (Client → kgateway → agentgateway → backend).

- **Windows**: `.\scripts\run-agentgateway.ps1`
- **Linux/macOS**: `./scripts/run-agentgateway.sh`

This mode measures additional proxy hop latency and agentgateway routing overhead.

> **Note**: This prototype focuses on TrafficPolicy-based extension attachment. Model-aware routing, multi-backend inference selection, and advanced EPP configurations are planned future extensions.

### Workflow Details

Each runner script executes the following stages:

1. **Environment Setup**: Creates (or recreates) a `kind` cluster using the local configuration.
2. **Component Installation**: Installs `kgateway` and required CRDs via Helm.
3. **Backend Deployment**: Deploys the `inference-backend` (Go-based 100ms delay server).
4. **Routing Configuration**: Applies the `Gateway` and specific `HTTPRoute` resources.
5. **Extension Attachment**: Optionally attaches the `TrafficPolicy` (inference benchmark only).
6. **Execution**: Initiates the `k6` load test against the gateway entrypoint.
7. **Persistence**: Stores raw console output and metrics in `results/`.

## 8. Benchmark Environment

All benchmarks should be referenced against this standard environment for reproducibility:

- **Environment**: Local Kubernetes cluster using `kind`
- **CPU**: 8 cores (host machine)
- **Memory**: 16 GB RAM
- **Load Generator**: k6
- **Virtual Users (VUs)**: 50
- **Test Duration**: 60 seconds
- **Gateway Version**: kgateway v2.3.0 (main branch build)

## 9. Results Summary

Since the backend introduces a **deterministic 100ms latency**, any duration above 100ms represents infrastructure overhead (proxy processing, TCP handshakes, and policy evaluation).

### Comparison Table

| Metric | Baseline (No Extension) | Inference (TrafficPolicy) | Agentgateway Path |
| :--- | :--- | :--- | :--- |
| **Median Latency (p50)** | 107.76 ms | 107.48 ms | 120.00 ms |
| **95th Percentile (p95)** | 112.23 ms | 113.06 ms | 169.06 ms |
| **99th Percentile (p99)** | 117.71 ms | 123.94 ms | 212.97 ms |
| **Throughput (RPS)** | 461.29 req/s | 461.52 req/s | 393.47 req/s |
| **Error Rate** | 0% | 0% | 0% |

## 10. Reproducing Exact Numbers

When running the benchmarks, k6 output will follow this pattern:

```text
     http_req_duration..............: avg=108.xxms p(50)=107.xxms p(95)=113.xxms p(99)=123.xxms
     http_req_failed................: 0.00%  ✓ 0          ✗ 27742
     http_reqs......................: 27742  461.519198/s
```

### Expected Approximate Ranges

- **Avg/p50**: ~105ms–110ms (reflects 100ms backend + ~5–10ms proxy/network overhead)
- **RPS**: ~450–470 req/s (at 50 Virtual Users)
- **Errors**: Should consistently be 0.00%.

## 11. Limitations

- **Local Environment**: High-percentile latency (p99) is subject to host system jitter and Docker Desktop resource scheduling.
- **Transport**: `kubectl port-forward` is used for simplicity but introduces overhead not present in production LoadBalancer environments.
- **Policy Scope**: The test utilizes a minimal extension policy; complex filters may increase processing time.

## 12. Streaming Inference Simulation

The benchmark supports simulating streaming responses typical of Large Language Models (LLMs) to evaluate how gateway policies affect streaming performance.

### Endpoint: `/infer-stream`

The backend simulates a streaming response with the following behavior:

1. **Immediate Headers**: Sends HTTP status and headers immediately.
2. **Deterministic TTFT**: Waits 50ms before sending the first chunk.
3. **Token Streaming**: Sends 20 small JSON chunks, each separated by a 10ms delay.

### Metrics Definitions

- **TTFT (Time To First Token)**: Time from the initial request until the first byte of response data arrives. This is the most critical metric for interactive LLM applications.
- **ITL (Inter-Token Latency)**: Average time between receiving consecutive chunks. High ITL leads to stuttering in the UI.
- **Total Duration**: Total time from request start to end of stream.

> [!IMPORTANT]
> This suite uses a deterministic CPU-based simulator. GPU-based real LLM benchmarking (e.g., vLLM, Ollama) is planned for future milestones.

### Streaming Comparison Table (Placeholder)

| Metric | Direct Access | Gateway Path | Extension Path |
| :--- | :--- | :--- | :--- |
| **Median TTFT (p50)** | ~55 ms | TBD | TBD |
| **95th TTFT (p95)** | ~60 ms | TBD | TBD |
| **Avg ITL** | ~10 ms | TBD | TBD |
| **Total Duration** | ~250 ms | TBD | TBD |

Direct Access values reflect expected simulator behavior (50ms TTFT + 10ms × 20 chunks). Gateway and Extension path values must be generated by running the streaming benchmark scripts locally.

### Standard Service Comparison Mode

To isolate latency added by the gateway vs. the raw service, use the direct comparison scripts:

- **Windows**: `.\scripts\run-direct.ps1`
- **Linux/macOS**: `./scripts/run-direct.sh`

### Routing Mode Comparison

| Mode | Routing Path |
| :--- | :--- |
| **Direct** | Client → Service |
| **Baseline** | Client → kgateway → backend |
| **Inference** | Client → kgateway + TrafficPolicy → backend |
| **Agentgateway** | Client → kgateway → agentgateway → backend |

Results are saved to `results/direct.txt` and `results/agentgateway.txt`.

## 13. Future Work

This prototype serves as a foundation for a comprehensive AI inference benchmarking framework. Planned enhancements:

- **GPU-backed Inference Benchmarking**: Integration with real GPU workloads using vLLM, Ollama, or NVIDIA Triton.
- **CI/CD Performance Regressions**: Automated nightly/weekly runs via GitHub Actions to detect data plane regressions.
- **Upstream Tooling Integration**: Alignment with [inference-perf](https://github.com/kubernetes-sigs/inference-perf) and industry-standard AI benchmarking tools.
- **Multi-Model Routing Experiments**: Measuring overhead for complex model-routing policies and A/B testing scenarios.
- **High-Concurrency Scaling**: Evaluating gateway stability under significantly higher concurrent loads (1000+ VUs).
- **Streaming Policy Impact**: Measuring how rate-limiting or header-injection affects stream throughput and ITL.

## 14. Alignment with Upstream Issue

This prototype addresses the foundational requirements discussed in [kgateway Issue #12289: Inference: Publish Benchmark Tests](https://github.com/kgateway-dev/kgateway/issues/12289).

Core objectives implemented from the upstream roadmap:

- **Reproducible Test Environment**: Standardized environment using `kind` and automated scripts.
- **Direct Metric Comparison**: Clear parity testing between raw service, baseline gateway, and extension paths.
- **AI Extension Profiling**: Measurement of `TrafficPolicy` overhead in the request path.
- **Advanced Inference Metrics**: Support for TTFT and ITL measurement via simulated streaming.

## 15. Repository Structure

```text
kgateway-inference-benchmark/
├── agentgateway/         # agentgateway (Rust data plane) manifests & config
│   ├── config.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── backend/              # 100ms delay simulator (Go)
│   ├── Dockerfile
│   ├── deployment.yaml
│   ├── main.go
│   └── service.yaml
├── gateway/              # Gateway API & kgateway resources
│   ├── gateway.yaml
│   ├── httproute-agentgateway.yaml
│   ├── httproute-baseline.yaml
│   ├── httproute-inference.yaml
│   └── trafficpolicy.yaml
├── loadtest/             # k6 test scripts
│   ├── baseline.js
│   └── streaming.js
├── results/              # Persisted benchmark raw results
│   ├── agentgateway.txt
│   ├── baseline.txt
│   ├── comparison.md
│   └── inference.txt
└── scripts/              # Automated runner scripts
    ├── run-agentgateway.ps1
    ├── run-agentgateway.sh
    ├── run-baseline.ps1
    ├── run-baseline.sh
    ├── run-direct.ps1
    ├── run-direct.sh
    ├── run-inference.ps1
    └── run-inference.sh

├── Makefile              # Management & CLI automation
├── README.md
└── kind-config.yaml      # Multi-node cluster configuration
```
