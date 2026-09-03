FROM python:3.13.13-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN adduser --disabled-password --gecos "" appuser

COPY src/requirements.txt ./requirements.txt

RUN python -m pip install --no-cache-dir --upgrade \
        -r requirements.txt \
        jaraco.context==6.1.0 \
        msgpack==1.2.1 \
        setuptools==78.1.1 \
        wheel==0.46.2

COPY --chown=appuser:appuser src/ ./src/

USER appuser

CMD ["python", "src/run.py"]
