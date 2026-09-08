"""Safe automated remediation executor."""

from __future__ import annotations

import logging
from typing import Any

from chaos import ChaosInjector, HEALTHY_ENV
from k8s_collector import K8sCollector

logger = logging.getLogger(__name__)

ALLOWED_DEPLOYMENTS = {"catalog-service", "orders-service", "inventory-service"}
ALLOWED_ENV_KEYS = {"DB_HOST", "DB_PORT", "DB_NAME", "FAIL_MODE"}
ALLOWED_ACTIONS = {"patch_env", "reset_env", "restart", "scale_up", "reset_all"}


class Remediator:
    def __init__(self):
        self.k8s = K8sCollector()
        self.chaos = ChaosInjector()

    def execute_action(self, action: dict[str, Any]) -> dict[str, Any]:
        action_type = action.get("action")
        deployment = action.get("deployment")

        if action_type not in ALLOWED_ACTIONS:
            return {"status": "skipped", "reason": f"action not allowed: {action_type}"}

        if action_type == "reset_all":
            return self.chaos.reset_all()

        if deployment and deployment not in ALLOWED_DEPLOYMENTS:
            return {"status": "skipped", "reason": f"deployment not allowed: {deployment}"}

        if action_type == "reset_env":
            result = self.chaos.reset_service(deployment)
            self.k8s.restart_deployment(deployment)
            return {"status": "reset_and_restarted", "deployment": deployment, "patch": result}

        if action_type == "restart":
            return self.k8s.restart_deployment(deployment)

        if action_type == "scale_up":
            replicas = int(action.get("replicas", 1))
            return self.k8s.scale_deployment(deployment, replicas)

        if action_type == "patch_env":
            env = action.get("env", {})
            safe_env = {k: str(v) for k, v in env.items() if k in ALLOWED_ENV_KEYS}
            if not safe_env:
                return {"status": "skipped", "reason": "no allowed env keys to patch"}
            result = self.k8s.patch_deployment_env(deployment, safe_env)
            self.k8s.restart_deployment(deployment)
            return {"status": "patched_and_restarted", "deployment": deployment, "env": safe_env, "patch": result}

        return {"status": "skipped", "reason": "unknown action"}

    def execute_plan(self, actions: list[dict[str, Any]]) -> dict[str, Any]:
        if any(a.get("action") == "reset_all" for a in actions):
            actions = [{"action": "reset_all", "risk": "low"}]

        results = []
        for action in actions:
            logger.info("Executing remediation action: %s", action)
            results.append({"action": action, "result": self.execute_action(action)})

        self.chaos._active = []
        return {"executed": len(results), "results": results}

    def build_actions_from_context(self, context: dict[str, Any]) -> list[dict[str, Any]]:
        """Rule-based remediation plan — works without OpenAI."""
        health = context.get("health", {})
        services = health.get("services", {})
        failing = [name for name, svc in services.items() if svc.get("status") != "healthy"]
        actions: list[dict[str, Any]] = []

        if not failing:
            return actions

        if context.get("active_injections") or len(failing) >= 2:
            return [{"action": "reset_all", "risk": "low"}]

        name = failing[0]
        dep = context.get("deployments", {}).get(name, {})
        if dep.get("ready_replicas", 1) == 0:
            actions.append({"action": "scale_up", "deployment": name, "replicas": 1, "risk": "low"})

        actions.append({"action": "reset_env", "deployment": name, "risk": "low"})
        return actions
