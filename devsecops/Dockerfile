FROM python:3.13-slim-bookworm

WORKDIR /app

COPY src/requirements.txt requirements.txt
RUN pip install --no-cache-dir --upgrade jaraco.context==6.1.0 wheel==0.46.2 msgpack==1.2.1 setuptools==78.1.1 -r requirements.txt && \
    apt-get update && \
    apt-get install -y --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY src/ src/

RUN adduser --disabled-password --gecos '' appuser && \
    chown -R appuser /app

USER appuser

CMD ["python", "src/run.py"]
