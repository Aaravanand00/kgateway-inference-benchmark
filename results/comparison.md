# Benchmark Comparison: kgateway Baseline vs. TrafficPolicy (Inference Layer)

## Comparison Table

| Metric | Baseline (No Extension) | Inference (TrafficPolicy) | Delta |
| :--- | :--- | :--- | :--- |
| **Median Latency (p50)** | 107.76 ms | 107.48 ms | -0.28 ms |
| **95th Percentile (p95)** | 112.23 ms | 113.06 ms | +0.83 ms |
| **99th Percentile (p99)** | 117.71 ms | 123.94 ms | +6.23 ms |
| **Average Latency (avg)** | 108.13 ms | 108.08 ms | -0.05 ms |
| **Throughput (RPS)** | 461.29 req/s | 461.52 req/s | +0.23 req/s |
| **Error Rate** | 0% | 0% | 0 |

## Technical Analysis

The introduction of a `TrafficPolicy` resource targeting the `HTTPRoute` does not negatively impact core gateway performance under the tested load (50 VUs). The delta in median latency is within noise and attributable to minor local environment variation during the test window.

## Overhead Estimation

Given the backend has a fixed artificial delay of 100ms:

- **Baseline Proxy Overhead (p50):** ~7.76ms
- **Inference Layer Overhead (p50):** ~7.48ms
- **Incremental Overhead:** Negligible (< 1ms)

The inference extension layer via kgateway's `TrafficPolicy` mechanism has a sub-millisecond footprint on the request path for the configuration tested.

## Stability Assessment

Both configurations exhibited high stability:

- **Error Consistency:** Zero failures across both 1-minute test runs.
- **Latency Spread:** The p99-to-p50 ratio remained within a healthy range (~1.10 for baseline, ~1.15 for inference), indicating the policy layer did not introduce significant tail latency or queuing issues.

## Limitations

1. **Local Node Jitter:** Benchmarks were conducted on a single Kind node (Docker Desktop); local resource contention may influence high-percentile results (p99).
2. **Policy Complexity:** This test used a minimal `TrafficPolicy`. More complex policies involving advanced filtering or transformations may yield different results.
3. **Port-forwarding Overhead:** `kubectl port-forward` introduces its own latency and throughput limitations compared to a native LoadBalancer environment.
