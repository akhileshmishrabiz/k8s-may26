FROM python:3.13.13-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

RUN apt-get update \
    && apt-get dist-upgrade -y \
    && addgroup --system appuser \
    && adduser --system --ingroup appuser --no-create-home appuser \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY src/requirements.txt ./requirements.txt

RUN python -m pip install --upgrade \
    -r requirements.txt \
    jaraco.context==6.1.0 \
    wheel==0.46.2

COPY --chown=appuser:appuser src/ ./src/

USER appuser

CMD ["python", "src/run.py"]
