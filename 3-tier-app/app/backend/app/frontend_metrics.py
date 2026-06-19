"""Prometheus metrics collected from browser telemetry."""

from prometheus_client import Counter, Histogram

FRONTEND_PAGE_VIEWS = Counter(
    "frontend_page_views_total",
    "SPA page views reported by the browser",
    ["route"],
)

FRONTEND_QUIZ_UI_EVENTS = Counter(
    "frontend_quiz_ui_events_total",
    "Quiz UI lifecycle events from the browser",
    ["event", "topic"],
)

FRONTEND_API_CLIENT_ERRORS = Counter(
    "frontend_api_client_errors_total",
    "Failed API calls observed in the browser",
    ["endpoint", "error_type"],
)

FRONTEND_WEB_VITALS = Histogram(
    "frontend_web_vitals_seconds",
    "Core Web Vitals reported by the browser",
    ["name", "rating"],
    buckets=(0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

FRONTEND_QUIZ_DURATION = Histogram(
    "frontend_quiz_duration_seconds",
    "Time spent in the quiz UI before completion or abandonment",
    ["topic", "outcome"],
    buckets=(10, 30, 60, 120, 300, 600, 1200, 1800),
)

ALLOWED_QUIZ_EVENTS = {"quiz_started", "quiz_completed", "quiz_abandoned"}
ALLOWED_WEB_VITALS = {"CLS", "FID", "FCP", "LCP", "TTFB", "INP"}


def record_page_view(route):
    route = (route or "/").strip() or "/"
    FRONTEND_PAGE_VIEWS.labels(route=route).inc()


def record_quiz_ui_event(event, topic=None):
    event = (event or "unknown").strip() or "unknown"
    if event not in ALLOWED_QUIZ_EVENTS:
        return
    topic_label = (topic or "unknown").strip() or "unknown"
    FRONTEND_QUIZ_UI_EVENTS.labels(event=event, topic=topic_label).inc()


def record_api_client_error(endpoint, error_type, status=None):
    endpoint = (endpoint or "unknown").strip() or "unknown"
    error_type = (error_type or "unknown").strip() or "unknown"
    if status and error_type == "http_error":
        endpoint = f"{endpoint} [{status}]"
    FRONTEND_API_CLIENT_ERRORS.labels(endpoint=endpoint, error_type=error_type).inc()


def record_web_vital(name, value_seconds, rating=None):
    name = (name or "unknown").strip().upper() or "unknown"
    if name not in ALLOWED_WEB_VITALS:
        return
    rating_label = (rating or "unknown").strip() or "unknown"
    try:
        value = float(value_seconds)
    except (TypeError, ValueError):
        return
    if value < 0:
        return
    FRONTEND_WEB_VITALS.labels(name=name, rating=rating_label).observe(value)


def record_quiz_duration(topic, outcome, duration_seconds):
    topic_label = (topic or "unknown").strip() or "unknown"
    outcome_label = (outcome or "unknown").strip() or "unknown"
    try:
        duration = float(duration_seconds)
    except (TypeError, ValueError):
        return
    if duration < 0:
        return
    FRONTEND_QUIZ_DURATION.labels(topic=topic_label, outcome=outcome_label).observe(duration)
