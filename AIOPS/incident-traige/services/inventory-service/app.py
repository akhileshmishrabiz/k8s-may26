import logging
import os
import time

from dotenv import load_dotenv
from flask import Flask, jsonify
from flask_cors import CORS
from pythonjsonlogger import jsonlogger
from sqlalchemy import text

from database import Stock, db

load_dotenv()

SERVICE_NAME = "inventory-service"
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
    f"{os.getenv('DB_NAME', 'inventory')}"
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


@app.route("/api/inventory", methods=["GET"])
def list_inventory():
    fail_response = apply_fail_mode()
    if fail_response:
        return fail_response

    items = Stock.query.order_by(Stock.product_id).all()
    return jsonify({"inventory": [item.to_dict() for item in items]}), 200


@app.route("/api/inventory/<int:product_id>", methods=["GET"])
def get_inventory(product_id):
    fail_response = apply_fail_mode()
    if fail_response:
        return fail_response

    item = Stock.query.filter_by(product_id=product_id).first()
    if not item:
        return jsonify({"error": f"no inventory record for product {product_id}"}), 404
    return jsonify(item.to_dict()), 200


def seed_data():
    if Stock.query.count() == 0:
        db.session.add_all([
            Stock(product_id=1, quantity=100),
            Stock(product_id=2, quantity=50),
        ])
        db.session.commit()
        logger.info("Seeded sample inventory")


with app.app_context():
    db.session.execute(text("CREATE SCHEMA IF NOT EXISTS inventory"))
    db.session.commit()
    db.create_all()
    seed_data()
    logger.info("Database initialized")


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5003))
    app.run(host="0.0.0.0", port=port)
