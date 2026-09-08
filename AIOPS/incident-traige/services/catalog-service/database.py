from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Product(db.Model):
    __tablename__ = "products"
    __table_args__ = {"schema": "catalog"}

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    price = db.Column(db.Numeric(10, 2), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "price": float(self.price),
            "created_at": self.created_at.isoformat() + "Z",
        }
