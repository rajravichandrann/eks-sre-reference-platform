import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    cpu_pressure: {
      executor: 'constant-vus',
      vus: 20,
      duration: '5m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<1500'],
  },
};

const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const response = http.get(`${baseUrl}/work?cpu_ms=100`);

  check(response, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.1);
}
