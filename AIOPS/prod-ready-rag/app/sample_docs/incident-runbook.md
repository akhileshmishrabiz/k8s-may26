# Incident Triage Runbook

## Purpose
This runbook describes the standard steps for triaging production incidents in a Kubernetes microservices environment.

## Severity Levels
- **SEV1**: Complete outage or data loss risk. Page on-call immediately.
- **SEV2**: Major feature degraded, workaround may exist.
- **SEV3**: Minor issue, fix in business hours.

## Triage Steps

### 1. Acknowledge and classify
- Confirm the alert or user report
- Assign severity and incident commander
- Create an incident channel and timeline

### 2. Check service health
- Review dashboard for failing health checks
- Identify which services are red vs degraded
- Note error rate spikes and latency changes

### 3. Inspect Kubernetes state
Run:
- `kubectl get pods -n <namespace>`
- `kubectl get events -n <namespace> --sort-by=.lastTimestamp`
- Check recent deployments and config changes

Look for CrashLoopBackOff, ImagePullBackOff, Pending pods, and failed readiness probes.

### 4. Collect logs and metrics
- Pull logs from failing pods (`kubectl logs` and `--previous`)
- Check dependency services (database, cache, upstream APIs)
- Review recent deploys, feature flags, and config map edits

### 5. Mitigate quickly
Preferred order:
1. Roll back the last deployment if a bad release is suspected
2. Scale up replicas if load-related
3. Restart unhealthy pods after confirming safe to do so
4. Toggle feature flags or circuit breakers if available

### 6. Communicate
- Post status updates every 15 minutes for SEV1/SEV2
- Document hypotheses, actions taken, and results

### 7. Resolve and follow up
- Confirm metrics and health checks are green
- Write a short post-incident summary
- Create action items for permanent fixes

## Common Patterns
| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| 502/503 from gateway | Downstream pod not ready | Check readiness probes and pod logs |
| DB connection errors | Credentials, network policy, or DB overload | Verify secrets and connection pool settings |
| Sudden latency spike | Resource saturation or noisy neighbor | Check CPU/memory and HPA status |

## Escalation
Escalate to platform/SRE if:
- Multiple namespaces affected
- Control plane or node issues suspected
- Persistent networking or storage failures
