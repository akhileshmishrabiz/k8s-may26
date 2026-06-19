import os
import time
import traceback

from flask import Flask, g, jsonify, request
from flask_cors import CORS
from flask_migrate import Migrate
from sqlalchemy import text
from werkzeug.exceptions import HTTPException

from .cloudwatch_metrics import emit_health_check_failure, emit_request_metrics
from .config import Config
from .logging_config import setup_logging
from .models import db
from .prometheus_metrics import metrics_response, record_http_request
from .request_context import init_request_context
from .routes import api_bp, leaderboard_bp, quiz_bp, telemetry_bp, topic_bp, wiki_bp

migrate = Migrate()
logger = setup_logging()

SKIP_METRICS_PATHS = {"/health", "/ready", "/metrics", "/api/telemetry"}


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    if os.getenv("ALLOWED_ORIGINS"):
        allowed_origins = os.getenv("ALLOWED_ORIGINS").split(",")
        logger.info("CORS allowing specific origins", extra={"origins": allowed_origins})
        CORS(app, origins=allowed_origins, supports_credentials=True)
    else:
        logger.info("CORS allowing all origins (development mode)")
        CORS(app)

    db.init_app(app)
    migrate.init_app(app, db)
    init_request_context(app)

    app.register_blueprint(topic_bp)
    app.register_blueprint(quiz_bp)
    app.register_blueprint(leaderboard_bp)
    app.register_blueprint(wiki_bp)
    app.register_blueprint(api_bp)
    app.register_blueprint(telemetry_bp)

    @app.before_request
    def before_request():
        request.start_time = time.time()

    @app.after_request
    def after_request(response):
        if request.path not in SKIP_METRICS_PATHS:
            duration_ms = (time.time() - request.start_time) * 1000
            duration_seconds = duration_ms / 1000
            endpoint = request.endpoint or "unknown"

            emit_request_metrics(
                method=request.method,
                endpoint=endpoint,
                status=response.status_code,
                duration_ms=duration_ms,
            )
            record_http_request(
                method=request.method,
                endpoint=endpoint,
                status=response.status_code,
                duration_seconds=duration_seconds,
            )

            logger.info(
                "request processed",
                extra={
                    "method": request.method,
                    "path": request.path,
                    "endpoint": endpoint,
                    "status": response.status_code,
                    "duration_ms": round(duration_ms, 2),
                    "request_id": getattr(g, "request_id", "-"),
                },
            )

        return response

    @app.errorhandler(HTTPException)
    def handle_http_exception(exc):
        return exc

    @app.errorhandler(Exception)
    def handle_exception(exc):
        logger.error(
            "unhandled exception",
            extra={
                "error": str(exc),
                "path": request.path,
                "method": request.method,
                "request_id": getattr(g, "request_id", "-"),
                "stack_trace": traceback.format_exc(),
            },
        )
        return jsonify({"error": "Internal server error"}), 500

    @app.route("/health", methods=["GET"])
    def health_check():
        try:
            db.session.execute(text("SELECT 1"))
            return {"status": "healthy", "database": "connected"}, 200
        except Exception as exc:
            emit_health_check_failure()
            logger.error(
                "health check failed",
                extra={
                    "error": str(exc),
                    "request_id": getattr(g, "request_id", "-"),
                },
            )
            return {"status": "unhealthy", "database": "disconnected"}, 503

    @app.route("/ready", methods=["GET"])
    def readiness_check():
        try:
            db.session.execute(text("SELECT 1"))
            return {"status": "ready", "database": "connected"}, 200
        except Exception as exc:
            logger.error(
                "readiness check failed",
                extra={
                    "error": str(exc),
                    "request_id": getattr(g, "request_id", "-"),
                },
            )
            return {"status": "not_ready", "database": "disconnected"}, 503

    @app.route("/metrics", methods=["GET"])
    def prometheus_metrics():
        body, status, headers = metrics_response()
        return body, status, headers

    return app
