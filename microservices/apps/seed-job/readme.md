# Seed job

One-shot container that waits for the API gateway, then POSTs 15 demo products.

## Docker Compose

Started automatically by `docker compose up` (see root `docker-compose.yml`).

Re-run manually:

```bash
docker compose run --rm seed-job
```

## Kubernetes

Build/load `microservices-seed-job:latest`, then:

```bash
kubectl apply -f apps/seed-job/seed-job.yaml
kubectl wait --for=condition=complete job/seed-job -n ecommerce --timeout=300s
kubectl logs job/seed-job -n ecommerce
```
