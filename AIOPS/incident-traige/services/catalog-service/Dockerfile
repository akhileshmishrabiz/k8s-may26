FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PORT=5001
EXPOSE 5001

CMD ["sh", "-c", "gunicorn -b 0.0.0.0:${PORT} app:app"]
