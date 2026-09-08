from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Stock(db.Model):
    __tablename__ = "stock"
    __table_args__ = {"schema": "inventory"}

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, nullable=False, unique=True)
    quantity = db.Column(db.Integer, nullable=False, default=0)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    def to_dict(self):
        return {
            "id": self.id,
            "product_id": self.product_id,
            "quantity": self.quantity,
            "updated_at": self.updated_at.isoformat() + "Z",
        }
