"""Chaos engineering / failure injection for the triage demo."""

from __future__ import annotations

from typing import Any

from k8s_collector import K8sCollector

HEALTHY_ENV = {
    "DB_HOST": "postgres",
    "DB_PORT": "5432",
    "DB_NAME": "triage",
    "FAIL_MODE": "none",
}

INJECTIONS: dict[str, dict[str, Any]] = {
    "db_unreachable": {
        "label": "Break DB connection",
        "description": "Point DB_HOST to a non-existent host",
        "targets": ["catalog-service", "orders-service", "inventory-service"],
        "env": {"DB_HOST": "postgres-broken.invalid.svc.cluster.local"},
    },
    "bad_credentials": {
        "label": "Bad DB credentials",
        "description": "Set wrong DB password",
        "targets": ["catalog-service"],
        "env": {"DB_PASSWORD": "wrong_password"},
    },
    "http_500": {
        "label": "HTTP 500 errors",
        "description": "Service returns 500 on all API calls",
        "targets": ["catalog-service"],
        "env": {"FAIL_MODE": "error"},
    },
    "high_latency": {
        "label": "High latency (5s)",
        "description": "Add 5 second delay to API responses",
        "targets": ["orders-service"],
        "env": {"FAIL_MODE": "latency"},
    },
    "crash_loop": {
        "label": "Crash loop",
        "description": "Service crashes on every health check",
        "targets": ["inventory-service"],
        "env": {"FAIL_MODE": "crash"},
    },
    "scale_to_zero": {
        "label": "Scale to zero",
        "description": "Scale deployment replicas to 0",
        "targets": ["catalog-service"],
        "action": "scale",
        "replicas": 0,
    },
}


class ChaosInjector:
    def __init__(self):
        self.k8s = K8sCollector()
        self._active: list[str] = []

    @property
    def injections(self) -> dict[str, dict[str, Any]]:
        return INJECTIONS

    @property
    def active(self) -> list[str]:
        return list(self._active)

    def inject(self, injection_id: str) -> dict[str, Any]:
        if injection_id not in INJECTIONS:
            return {"error": f"Unknown injection: {injection_id}"}

        spec = INJECTIONS[injection_id]
        results = []

        if spec.get("action") == "scale":
            for target in spec["targets"]:
                result = self.k8s.scale_deployment(target, spec["replicas"])
                results.append(result)
        else:
            for target in spec["targets"]:
                result = self.k8s.patch_deployment_env(target, spec.get("env", {}))
                results.append(result)
                results.append(self.k8s.restart_deployment(target))

        if injection_id not in self._active:
            self._active.append(injection_id)
        return {"injection": injection_id, "results": results}

    def reset_all(self) -> dict[str, Any]:
        results = []
        for deployment in ["catalog-service", "orders-service", "inventory-service"]:
            results.append(self.k8s.patch_deployment_env(deployment, HEALTHY_ENV))
            results.append(self.k8s.scale_deployment(deployment, 1))
            results.append(self.k8s.restart_deployment(deployment))
        self._active = []
        return {"status": "reset", "results": results}

    def reset_service(self, deployment: str) -> dict[str, Any]:
        result = self.k8s.patch_deployment_env(deployment, HEALTHY_ENV)
        scale = self.k8s.scale_deployment(deployment, 1)
        return {"deployment": deployment, "patch": result, "scale": scale}
