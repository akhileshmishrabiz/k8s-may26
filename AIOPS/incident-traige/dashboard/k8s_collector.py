"""Kubernetes data collector for incident triage."""

from __future__ import annotations

import logging
from typing import Any

from kubernetes import client, config
from kubernetes.client.rest import ApiException

logger = logging.getLogger(__name__)

NAMESPACE = "incident-triage"
SERVICES = {
    "catalog-service": {"deployment": "catalog-service", "port": 5001, "path": "/api/products"},
    "orders-service": {"deployment": "orders-service", "port": 5002, "path": "/api/orders"},
    "inventory-service": {"deployment": "inventory-service", "port": 5003, "path": "/api/inventory"},
    "postgres": {"deployment": "postgres", "port": 5432, "path": None},
}


class K8sCollector:
    def __init__(self, namespace: str = NAMESPACE):
        self.namespace = namespace
        self._loaded = False
        self.apps_v1: client.AppsV1Api | None = None
        self.core_v1: client.CoreV1Api | None = None

    def _ensure_client(self) -> None:
        if self._loaded:
            return
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        self.apps_v1 = client.AppsV1Api()
        self.core_v1 = client.CoreV1Api()
        self._loaded = True

    def get_deployment_status(self, name: str) -> dict[str, Any]:
        self._ensure_client()
        assert self.apps_v1 is not None
        try:
            if name == "postgres":
                sts = self.apps_v1.read_namespaced_stateful_set(name, self.namespace)
                return {
                    "name": name,
                    "kind": "StatefulSet",
                    "replicas": sts.spec.replicas,
                    "ready_replicas": sts.status.ready_replicas or 0,
                    "available_replicas": sts.status.ready_replicas or 0,
                    "conditions": [],
                }
            dep = self.apps_v1.read_namespaced_deployment(name, self.namespace)
            return {
                "name": name,
                "kind": "Deployment",
                "replicas": dep.spec.replicas,
                "ready_replicas": dep.status.ready_replicas or 0,
                "available_replicas": dep.status.available_replicas or 0,
                "conditions": [
                    {"type": c.type, "status": c.status, "reason": c.reason, "message": c.message}
                    for c in (dep.status.conditions or [])
                ],
            }
        except ApiException as exc:
            return {"name": name, "error": exc.reason}

    def get_pod_info(self, deployment: str) -> list[dict[str, Any]]:
        self._ensure_client()
        assert self.core_v1 is not None
        try:
            pods = self.core_v1.list_namespaced_pod(
                self.namespace,
                label_selector=f"app={deployment}",
            )
            result = []
            for pod in pods.items:
                restarts = sum(c.restart_count for c in (pod.status.container_statuses or []))
                result.append(
                    {
                        "name": pod.metadata.name,
                        "phase": pod.status.phase,
                        "restarts": restarts,
                        "node": pod.spec.node_name,
                        "ready": all(
                            cs.ready for cs in (pod.status.container_statuses or [])
                        ),
                    }
                )
            return result
        except ApiException as exc:
            return [{"error": exc.reason}]

    def get_pod_logs(self, deployment: str, tail_lines: int = 80) -> str:
        self._ensure_client()
        assert self.core_v1 is not None
        pods = self.get_pod_info(deployment)
        if not pods or "error" in pods[0]:
            return f"No pods found for {deployment}"
        pod_name = pods[0]["name"]
        try:
            return self.core_v1.read_namespaced_pod_log(
                pod_name, self.namespace, tail_lines=tail_lines
            )
        except ApiException as exc:
            return f"Failed to fetch logs: {exc.reason}"

    def get_events(self, deployment: str) -> list[dict[str, Any]]:
        self._ensure_client()
        assert self.core_v1 is not None
        try:
            events = self.core_v1.list_namespaced_event(self.namespace)
            filtered = []
            for event in events.items:
                involved = event.involved_object
                if involved and involved.name and deployment in involved.name:
                    filtered.append(
                        {
                            "type": event.type,
                            "reason": event.reason,
                            "message": event.message,
                            "time": str(event.last_timestamp or event.event_time),
                        }
                    )
            return sorted(filtered, key=lambda e: e["time"], reverse=True)[:15]
        except ApiException as exc:
            return [{"error": exc.reason}]

    def _container_env_list(self, deployment: str, env_updates: dict[str, str]) -> tuple[str, list[dict[str, Any]]]:
        dep = self.apps_v1.read_namespaced_deployment(deployment, self.namespace)
        container = dep.spec.template.spec.containers[0]
        merged: dict[str, dict[str, Any]] = {}
        for item in container.env or []:
            entry: dict[str, Any] = {"name": item.name}
            if item.value_from is not None:
                entry["valueFrom"] = item.value_from.to_dict()
            elif item.value is not None:
                entry["value"] = item.value
            merged[item.name] = entry
        for key, value in env_updates.items():
            merged[key] = {"name": key, "value": value}
        return container.name, list(merged.values())

    def patch_deployment_env(self, deployment: str, env_updates: dict[str, str]) -> dict[str, Any]:
        self._ensure_client()
        assert self.apps_v1 is not None
        try:
            container_name, env_list = self._container_env_list(deployment, env_updates)
            patch = {
                "spec": {
                    "template": {
                        "spec": {
                            "containers": [{"name": container_name, "env": env_list}]
                        }
                    }
                }
            }
            self.apps_v1.patch_namespaced_deployment(deployment, self.namespace, patch)
            return {"status": "patched", "deployment": deployment, "env": env_updates}
        except ApiException as exc:
            return {"error": exc.reason, "body": exc.body}

    def scale_deployment(self, deployment: str, replicas: int) -> dict[str, Any]:
        self._ensure_client()
        assert self.apps_v1 is not None
        try:
            patch = {"spec": {"replicas": replicas}}
            self.apps_v1.patch_namespaced_deployment(deployment, self.namespace, patch)
            return {"status": "scaled", "deployment": deployment, "replicas": replicas}
        except ApiException as exc:
            return {"error": exc.reason, "body": exc.body}

    def restart_deployment(self, deployment: str) -> dict[str, Any]:
        self._ensure_client()
        assert self.apps_v1 is not None
        try:
            import datetime

            patch = {
                "spec": {
                    "template": {
                        "metadata": {
                            "annotations": {
                                "kubectl.kubernetes.io/restartedAt": datetime.datetime.utcnow().isoformat()
                            }
                        }
                    }
                }
            }
            self.apps_v1.patch_namespaced_deployment(deployment, self.namespace, patch)
            return {"status": "restarted", "deployment": deployment}
        except ApiException as exc:
            return {"error": exc.reason, "body": exc.body}
