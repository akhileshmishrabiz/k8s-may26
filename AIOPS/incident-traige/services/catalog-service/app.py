import logging
import os
import time

from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from pythonjsonlogger import jsonlogger
from sqlalchemy import text

from database import Product, db

load_dotenv()

SERVICE_NAME = "catalog-service"
FAIL_MODE = os.getenv("FAIL_MODE", "none").lower()
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

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
    f"{os.getenv('DB_NAME', 'catalog')}"
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


@app.route("/health", methods=["GET"])
def health():
    if FAIL_MODE == "crash":
        logger.error("FAIL_MODE=crash triggered on /health")
        os._exit(1)
    return jsonify({"status": "ok", "service": SERVICE_NAME}), 200


@app.route("/ready", methods=["GET"])
def ready():
    try:
        check_db()
        return jsonify({"status": "ready", "service": SERVICE_NAME, "database": "connected"}), 200
    except Exception as exc:
        logger.exception("Readiness check failed")
        return jsonify(
            {"status": "not_ready", "service": SERVICE_NAME, "database": "disconnected", "error": str(exc)}
        ), 503


@app.route("/api/products", methods=["GET"])
def list_products():
    fail_response = apply_fail_mode()
    if fail_response:
        return fail_response

    products = Product.query.order_by(Product.id).all()
    return jsonify({"products": [product.to_dict() for product in products]}), 200


@app.route("/api/products", methods=["POST"])
def create_product():
    fail_response = apply_fail_mode()
    if fail_response:
        return fail_response

    payload = request.get_json(silent=True) or {}
    name = payload.get("name")
    price = payload.get("price")

    if not name or price is None:
        return jsonify({"error": "name and price are required"}), 400

    try:
        price = float(price)
    except (TypeError, ValueError):
        return jsonify({"error": "price must be a number"}), 400

    product = Product(name=name, price=price)
    db.session.add(product)
    db.session.commit()
    logger.info("Product created", extra={"product_id": product.id, "name": name})
    return jsonify(product.to_dict()), 201


def seed_data():
    if Product.query.count() == 0:
        db.session.add_all([
            Product(name="Widget A", price=19.99),
            Product(name="Widget B", price=29.99),
        ])
        db.session.commit()
        logger.info("Seeded sample products")


with app.app_context():
    db.session.execute(text("CREATE SCHEMA IF NOT EXISTS catalog"))
    db.session.commit()
    db.create_all()
    seed_data()
    logger.info("Database initialized")


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5001))
    app.run(host="0.0.0.0", port=port)
