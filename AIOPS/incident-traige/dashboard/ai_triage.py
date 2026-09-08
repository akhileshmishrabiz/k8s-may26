"""OpenAI-powered incident triage."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an expert SRE performing incident triage on a Kubernetes microservices demo.
Analyze the provided health data, pod status, events, and logs.
Respond in JSON with these fields:
- summary: one-line status
- severity: P1|P2|P3
- root_cause: most likely root cause
- evidence: list of supporting evidence from logs/events
- remediation_steps: ordered list of human-readable fix steps
- remediation_actions: list of automated fix actions the system can execute. Each action object must use ONLY these types:
  - {"action":"patch_env","deployment":"catalog-service|orders-service|inventory-service","env":{"FAIL_MODE":"none"} or {"DB_HOST":"postgres"} etc,"risk":"low"}
  - {"action":"reset_env","deployment":"...","risk":"low"}
  - {"action":"restart","deployment":"...","risk":"low"}
  - {"action":"scale_up","deployment":"...","replicas":1,"risk":"low"}
  - {"action":"reset_all","risk":"low"} — restores all services to healthy defaults
Allowed env keys: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, FAIL_MODE.
Healthy defaults: DB_HOST=postgres, DB_PORT=5432, DB_NAME=triage, FAIL_MODE=none.
Only suggest actions you are confident will fix the issue. Prefer reset_all when multiple services fail due to DB chaos.
- confidence: low|medium|high
Be concise and actionable. Focus on the failing service(s)."""


class AITriage:
    def __init__(self):
        self.api_key = os.getenv("OPENAI_API_KEY", "")
        self.model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

    @property
    def available(self) -> bool:
        placeholders = ("sk-your", "sk-replace-me")
        return bool(self.api_key and not self.api_key.startswith(placeholders))

    async def analyze(self, context: dict[str, Any]) -> dict[str, Any]:
        if not self.available:
            return self._fallback_analysis(context)

        try:
            from openai import AsyncOpenAI

            client = AsyncOpenAI(api_key=self.api_key)
            response = await client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": f"Analyze this incident context:\n\n{json.dumps(context, indent=2, default=str)}",
                    },
                ],
                response_format={"type": "json_object"},
                temperature=0.2,
            )
            content = response.choices[0].message.content or "{}"
            return json.loads(content)
        except Exception as exc:
            logger.exception("OpenAI triage failed")
            result = self._fallback_analysis(context)
            result["ai_error"] = str(exc)
            return result

    def _fallback_analysis(self, context: dict[str, Any]) -> dict[str, Any]:
        """Rule-based fallback when OpenAI is unavailable."""
        health = context.get("health", {})
        services = health.get("services", {})
        failing = [name for name, svc in services.items() if svc.get("status") != "healthy"]

        if not failing:
            return {
                "summary": "All services appear healthy",
                "severity": "P3",
                "root_cause": "No active failures detected",
                "evidence": [],
                "remediation_steps": ["Continue monitoring"],
                "remediation_actions": [],
                "confidence": "high",
                "mode": "rule-based",
            }

        steps = []
        evidence = []
        for name in failing:
            svc = services[name]
            for err in svc.get("errors", []):
                evidence.append(f"{name}: {err}")
            if any("500" in e for e in svc.get("errors", [])):
                steps.append(f"Check {name} FAIL_MODE env — set FAIL_MODE=none to restore")
                steps.append(f"kubectl rollout restart deployment/{name} -n incident-triage")
            if any("Connection" in e or "connect" in e.lower() for e in svc.get("errors", [])):
                steps.append("Verify postgres StatefulSet is running: kubectl get pods -n incident-triage -l app=postgres")
                steps.append("Check DB_HOST env on failing deployment")
            if any("timeout" in e.lower() or "latency" in e.lower() for e in svc.get("errors", [])):
                steps.append(f"Check {name} for FAIL_MODE=latency — patch back to none")

        events = context.get("events", {})
        for dep, evts in events.items():
            for evt in evts[:3]:
                if evt.get("reason") in ("BackOff", "CrashLoopBackOff", "Failed"):
                    evidence.append(f"{dep} event: {evt.get('reason')} — {evt.get('message', '')[:100]}")
                    steps.append(f"kubectl logs -l app={dep} -n incident-triage --tail=50")

        if not steps:
            steps = [f"kubectl describe deployment {name} -n incident-triage" for name in failing]

        from remediator import Remediator

        actions = Remediator().build_actions_from_context(context)

        return {
            "summary": f"{len(failing)} service(s) unhealthy: {', '.join(failing)}",
            "severity": "P1" if len(failing) > 1 else "P2",
            "root_cause": f"Failure detected in {', '.join(failing)}",
            "evidence": evidence[:10],
            "remediation_steps": steps[:8],
            "remediation_actions": actions,
            "confidence": "medium",
            "mode": "rule-based",
        }
