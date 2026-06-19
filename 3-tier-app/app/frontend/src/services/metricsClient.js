import API_URL from '../config/api';

const TELEMETRY_URL = `${API_URL}/api/telemetry`;
const TELEMETRY_ENABLED = process.env.NODE_ENV !== 'test';
const FLUSH_INTERVAL_MS = 5000;
const MAX_BATCH_SIZE = 10;

const queue = [];
let flushTimer = null;
let unloadHookInstalled = false;

function normalizeEndpoint(url) {
  try {
    const parsed = new URL(url, window.location.origin);
    return parsed.pathname;
  } catch {
    return String(url || 'unknown');
  }
}

function enqueue(event) {
  if (!TELEMETRY_ENABLED) {
    return;
  }
  queue.push({ ...event, ts: Date.now() });
  if (queue.length >= MAX_BATCH_SIZE) {
    flushTelemetry();
    return;
  }
  scheduleFlush();
}

function scheduleFlush() {
  if (flushTimer) {
    return;
  }
  flushTimer = window.setTimeout(() => {
    flushTimer = null;
    flushTelemetry();
  }, FLUSH_INTERVAL_MS);
}

function sendPayload(payload, useBeacon = false) {
  const body = JSON.stringify(payload);
  if (useBeacon && navigator.sendBeacon) {
    const blob = new Blob([body], { type: 'application/json' });
    return navigator.sendBeacon(TELEMETRY_URL, blob);
  }
  return fetch(TELEMETRY_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
    keepalive: true,
  }).catch(() => false);
}

export function flushTelemetry(useBeacon = false) {
  if (!TELEMETRY_ENABLED || queue.length === 0) {
    return;
  }

  const events = queue.splice(0, MAX_BATCH_SIZE);
  if (flushTimer) {
    window.clearTimeout(flushTimer);
    flushTimer = null;
  }

  sendPayload({ events }, useBeacon);

  if (queue.length > 0) {
    scheduleFlush();
  }
}

function installUnloadHook() {
  if (unloadHookInstalled || !TELEMETRY_ENABLED) {
    return;
  }
  unloadHookInstalled = true;
  window.addEventListener('pagehide', () => flushTelemetry(true));
  window.addEventListener('beforeunload', () => flushTelemetry(true));
}

export function recordPageView(route) {
  installUnloadHook();
  enqueue({ type: 'page_view', route: route || '/' });
}

export function recordQuizUiEvent(event, topic) {
  installUnloadHook();
  enqueue({ type: 'quiz_ui_event', event, topic: topic || 'unknown' });
}

export function recordQuizDuration(topic, outcome, durationSeconds) {
  installUnloadHook();
  enqueue({
    type: 'quiz_duration',
    topic: topic || 'unknown',
    outcome: outcome || 'unknown',
    duration_seconds: durationSeconds,
  });
}

export function recordApiClientError(endpoint, errorType, status) {
  installUnloadHook();
  enqueue({
    type: 'api_client_error',
    endpoint: endpoint || 'unknown',
    error_type: errorType || 'unknown',
    status: status ? String(status) : undefined,
  });
}

export function recordWebVital(name, value, rating) {
  installUnloadHook();
  enqueue({
    type: 'web_vital',
    name,
    value,
    rating: rating || 'unknown',
  });
}

export async function instrumentedFetch(url, options = {}) {
  const endpoint = normalizeEndpoint(url);
  try {
    const response = await fetch(url, options);
    if (!response.ok) {
      recordApiClientError(endpoint, 'http_error', response.status);
    }
    return response;
  } catch (error) {
    recordApiClientError(endpoint, 'network_error');
    throw error;
  }
}
