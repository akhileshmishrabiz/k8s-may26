import uuid

from flask import g, request


def init_request_context(app):
    @app.before_request
    def assign_request_id():
        incoming = request.headers.get("X-Request-ID", "").strip()
        g.request_id = incoming or str(uuid.uuid4())

    @app.after_request
    def attach_request_id(response):
        if hasattr(g, "request_id"):
            response.headers["X-Request-ID"] = g.request_id
        return response
