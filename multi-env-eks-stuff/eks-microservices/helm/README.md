# E-commerce Microservices Helm Chart (deprecated)

> **This umbrella chart is deprecated.** Use the split layout instead:
>
> - **Services only:** `../helm-services/` (deployed via ArgoCD)
> - **Databases / Redis / RabbitMQ:** `../infra/ms-ecom/databases.tf` (Terraform)

This chart previously deployed everything in one release. It is kept for reference during migration.

## Migration

1. Apply `infra/vault-secrets/` (ESO secrets must exist)
2. Apply `infra/ms-ecom/` (`databases.tf` provisions CNPG, Redis, RabbitMQ)
3. Point ArgoCD at `eks-microservices/helm-services` (default in `ms-ecom/variables.tf`)
4. Remove the old Helm release or let ArgoCD prune DB resources no longer in the new chart

Service env vars and secret references are unchanged — same secret names (`db-credentials`, `redis-credentials`, etc.) and same service DNS names (`products-rw`, `redis`, `rabbitmq`).

See `../helm-services/README.md` and `../infra/README.md` for the current deploy flow.
