"""Prometheus metrics for the DevOps quiz backend."""

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

HTTP_REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

QUIZ_STARTS = Counter(
    "quiz_starts_total",
    "Quiz sessions started",
    ["topic"],
)

QUIZ_SUBMISSIONS = Counter(
    "quiz_submissions_total",
    "Quiz submissions graded",
    ["topic", "result"],
)

LEADERBOARD_LOOKUPS = Counter(
    "leaderboard_lookups_total",
    "Leaderboard API lookups",
    ["scope"],
)


def record_http_request(method, endpoint, status, duration_seconds):
    endpoint = endpoint or "unknown"
    status_label = str(status)
    HTTP_REQUESTS.labels(method=method, endpoint=endpoint, status=status_label).inc()
    HTTP_REQUEST_DURATION.labels(method=method, endpoint=endpoint).observe(duration_seconds)


def record_quiz_start(topic):
    QUIZ_STARTS.labels(topic=topic).inc()


def record_quiz_submission(topic, passed):
    result = "pass" if passed else "fail"
    QUIZ_SUBMISSIONS.labels(topic=topic, result=result).inc()


def record_leaderboard_lookup(scope):
    LEADERBOARD_LOOKUPS.labels(scope=scope).inc()


def metrics_response():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}
