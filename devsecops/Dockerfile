# docker file for aiops day 1
FROM python:3.11-slim

WORKDIR /app

COPY src/requirements.txt requirements.txt
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

COPY src/ src/

CMD ["python", "src/run.py"]