from flask import jsonify, request

from app.frontend_metrics import (
    record_api_client_error,
    record_page_view,
    record_quiz_duration,
    record_quiz_ui_event,
    record_web_vital,
)
from app.logging_config import setup_logging

from . import telemetry_bp

logger = setup_logging()

MAX_EVENTS_PER_REQUEST = 50


def _handle_event(event):
    event_type = event.get("type")
    if event_type == "page_view":
        record_page_view(event.get("route"))
        return True
    if event_type == "quiz_ui_event":
        record_quiz_ui_event(event.get("event"), event.get("topic"))
        return True
    if event_type == "api_client_error":
        record_api_client_error(
            event.get("endpoint"),
            event.get("error_type"),
            event.get("status"),
        )
        return True
    if event_type == "web_vital":
        record_web_vital(event.get("name"), event.get("value"), event.get("rating"))
        return True
    if event_type == "quiz_duration":
        record_quiz_duration(
            event.get("topic"),
            event.get("outcome"),
            event.get("duration_seconds"),
        )
        return True
    return False


@telemetry_bp.route("", methods=["POST"])
def ingest_telemetry():
    payload = request.get_json(silent=True) or {}
    events = payload.get("events")

    if not isinstance(events, list) or not events:
        return jsonify({"error": "events must be a non-empty list"}), 400
    if len(events) > MAX_EVENTS_PER_REQUEST:
        return jsonify({"error": f"at most {MAX_EVENTS_PER_REQUEST} events per request"}), 400

    accepted = 0
    for event in events:
        if isinstance(event, dict) and _handle_event(event):
            accepted += 1

    logger.debug(
        "frontend telemetry ingested",
        extra={
            "event": "frontend_telemetry",
            "received": len(events),
            "accepted": accepted,
        },
    )

    return jsonify({"accepted": accepted, "received": len(events)}), 202
