from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Order(db.Model):
    __tablename__ = "orders"
    __table_args__ = {"schema": "orders"}

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, nullable=False)
    quantity = db.Column(db.Integer, nullable=False)
    status = db.Column(db.String(50), nullable=False, default="pending")
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "product_id": self.product_id,
            "quantity": self.quantity,
            "status": self.status,
            "created_at": self.created_at.isoformat() + "Z",
        }
