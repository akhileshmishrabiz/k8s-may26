import logging
import os
import time

import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from pythonjsonlogger import jsonlogger
from sqlalchemy import text

from database import Order, db

load_dotenv()

SERVICE_NAME = "orders-service"
FAIL_MODE = os.getenv("FAIL_MODE", "none").lower()
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
CATALOG_SERVICE_URL = os.getenv("CATALOG_SERVICE_URL", "http://catalog-service:5001")

log_handler = logging.StreamHandler()
log_handler.setFormatter(
    jsonlogger.JsonFormatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s",
        rename_fields={"asctime": "timestamp", "levelname": "level"},
        static_fields={"service": SERVICE_NAME},
    )
)
logging.basicConfig(level=LOG_LEVEL, handlers=[log_handler], force=True)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

app.config["SQLALCHEMY_DATABASE_URI"] = (
    f"postgresql://{os.getenv('DB_USER', 'postgres')}:"
    f"{os.getenv('DB_PASSWORD', 'postgres')}@"
    f"{os.getenv('DB_HOST', 'localhost')}:"
    f"{os.getenv('DB_PORT', '5432')}/"
    f"{os.getenv('DB_NAME', 'orders')}"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)


def apply_fail_mode():
    if FAIL_MODE == "latency":
        time.sleep(5)
    elif FAIL_MODE == "error":
        return jsonify({"error": "simulated failure", "service": SERVICE_NAME}), 500
    return None


def check_db():
    db.session.execute(text("SELECT 1"))
    return True


def check_catalog_health():
    response = requests.get(f"{CATALOG_SERVICE_URL}/health", timeout=3)
    response.raise_for_status()
    return True


def product_exists(product_id):
    response = requests.get(f"{CATALOG_SERVICE_URL}/api/products", timeout=5)
    response.raise_for_status()
    products = response.json().get("products", [])
    return any(product["id"] == product_id for product in products)


@app.route("/health", methods=["GET"])
def health():
    if FAIL_MODE == "crash":
        logger.error("FAIL_MODE=crash triggered on /health")
        os._exit(1)
    return jsonify({"status": "ok", "service": SERVICE_NAME}), 200


@app.route("/ready", methods=["GET"])
def ready():
    checks = {"database": "disconnected", "catalog": "disconnected"}
    try:
        check_db()
        checks["database"] = "connected"
        check_catalog_health()
        checks["catalog"] = "connected"
        return jsonify({"status": "ready", "service": SERVICE_NAME, **checks}), 200
    except Exception as exc:
        logger.exception("Readiness check failed")
        return jsonify(
            {"status": "not_ready", "service": SERVICE_NAME, **checks, "error": str(exc)}
        ), 503


@app.route("/api/orders", methods=["GET"])
def list_orders():
    fail_response = apply_fail_mode()
    if fail_response:
        return fail_response

    orders = Order.query.order_by(Order.id).all()
    return jsonify({"orders": [order.to_dict() for order in orders]}), 200


@app.route("/api/orders", methods=["POST"])
def create_order():
    fail_response = apply_fail_mode()
    if fail_response:
        return fail_response

    payload = request.get_json(silent=True) or {}
    product_id = payload.get("product_id")
    quantity = payload.get("quantity")

    if product_id is None or quantity is None:
        return jsonify({"error": "product_id and quantity are required"}), 400

    try:
        product_id = int(product_id)
        quantity = int(quantity)
    except (TypeError, ValueError):
        return jsonify({"error": "product_id and quantity must be integers"}), 400

    if quantity <= 0:
        return jsonify({"error": "quantity must be greater than zero"}), 400

    try:
        if not product_exists(product_id):
            return jsonify({"error": f"product {product_id} not found in catalog"}), 404
    except requests.RequestException as exc:
        logger.exception("Catalog service unavailable during order validation")
        return jsonify({"error": "catalog service unavailable", "details": str(exc)}), 502

    order = Order(product_id=product_id, quantity=quantity, status="pending")
    db.session.add(order)
    db.session.commit()
    logger.info("Order created", extra={"order_id": order.id, "product_id": product_id})
    return jsonify(order.to_dict()), 201


with app.app_context():
    db.session.execute(text("CREATE SCHEMA IF NOT EXISTS orders"))
    db.session.commit()
    db.create_all()
    logger.info("Database initialized")


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5002))
    app.run(host="0.0.0.0", port=port)
