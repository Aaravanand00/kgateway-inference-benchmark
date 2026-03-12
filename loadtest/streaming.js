import http from 'k6/http';
import { Trend } from 'k6/metrics';
import { check, sleep } from 'k6';

// TTFB is used as a proxy for TTFT in streaming inference benchmarks.
const ttftTrend = new Trend('time_to_first_byte', true);

export const options = {
  vus: 10,
  duration: '30s',
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)'],
};

export default function () {
  const url = __ENV.TARGET_URL || 'http://localhost:8081/infer-stream';

  const res = http.get(url);

  check(res, {
    'is status 200': (r) => r.status === 200,
  });

  ttftTrend.add(res.timings.waiting);

  sleep(0.5);
}
