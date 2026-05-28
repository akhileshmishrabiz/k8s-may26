#!/usr/bin/env bash
set -euo pipefail

export DB_LINK="${DB_LINK:-sqlite:////tmp/student_portal.db}"
export SECRET_KEY="${SECRET_KEY:-dev-only-change-in-production}"

exec gunicorn --bind 0.0.0.0:8000 run:app
