"""Health monitoring for microservices."""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

import httpx

logger = logging.getLogger(__name__)

SERVICE_URLS = {
    "catalog-service": "http://catalog-service.incident-triage.svc.cluster.local:5001",
    "orders-service": "http://orders-service.incident-triage.svc.cluster.local:5002",
    "inventory-service": "http://inventory-service.incident-triage.svc.cluster.local:5003",
}

LOCAL_URLS = {
    "catalog-service": "http://localhost:5001",
    "orders-service": "http://localhost:5002",
    "inventory-service": "http://localhost:5003",
}


class HealthMonitor:
    def __init__(self, use_local: bool = False, timeout: float = 5.0):
        self.urls = LOCAL_URLS if use_local else SERVICE_URLS
        self.timeout = timeout
        self._cache: dict[str, Any] = {}
        self._incidents: list[dict[str, Any]] = []

    async def check_service(self, name: str, client: httpx.AsyncClient) -> dict[str, Any]:
        base = self.urls[name]
        result: dict[str, Any] = {
            "name": name,
            "status": "healthy",
            "health": None,
            "ready": None,
            "api": None,
            "latency_ms": {},
            "errors": [],
        }

        for endpoint, key in [("/health", "health"), ("/ready", "ready")]:
            start = time.perf_counter()
            try:
                resp = await client.get(f"{base}{endpoint}")
                elapsed = round((time.perf_counter() - start) * 1000, 1)
                result["latency_ms"][key] = elapsed
                result[key] = {"status_code": resp.status_code, "body": resp.text[:500]}
                if resp.status_code >= 400:
                    result["status"] = "unhealthy"
                    result["errors"].append(f"{endpoint} returned {resp.status_code}")
            except Exception as exc:
                result["status"] = "unhealthy"
                result[key] = {"error": str(exc)}
                result["errors"].append(f"{endpoint}: {exc}")

        api_paths = {
            "catalog-service": "/api/products",
            "orders-service": "/api/orders",
            "inventory-service": "/api/inventory",
        }
        api_path = api_paths.get(name)
        if api_path:
            start = time.perf_counter()
            try:
                resp = await client.get(f"{base}{api_path}")
                elapsed = round((time.perf_counter() - start) * 1000, 1)
                result["latency_ms"]["api"] = elapsed
                result["api"] = {"status_code": resp.status_code, "body": resp.text[:300]}
                if resp.status_code >= 500:
                    result["status"] = "degraded" if result["status"] == "healthy" else result["status"]
                    if result["status"] == "healthy":
                        result["status"] = "unhealthy"
                    result["errors"].append(f"API returned {resp.status_code}")
            except Exception as exc:
                result["status"] = "unhealthy"
                result["api"] = {"error": str(exc)}
                result["errors"].append(f"API: {exc}")

        return result

    async def check_all(self) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            tasks = [self.check_service(name, client) for name in self.urls]
            results = await asyncio.gather(*tasks)

        summary = {
            "timestamp": time.time(),
            "overall": "healthy",
            "services": {r["name"]: r for r in results},
        }
        unhealthy = [r for r in results if r["status"] != "healthy"]
        if unhealthy:
            summary["overall"] = "unhealthy"
            for svc in unhealthy:
                self._record_incident(svc)

        self._cache = summary
        return summary

    def _record_incident(self, svc: dict[str, Any]) -> None:
        incident = {
            "time": time.time(),
            "service": svc["name"],
            "status": svc["status"],
            "errors": svc["errors"],
        }
        if not self._incidents or self._incidents[-1].get("service") != svc["name"]:
            self._incidents.append(incident)
        elif self._incidents[-1].get("errors") != svc["errors"]:
            self._incidents.append(incident)
        self._incidents = self._incidents[-50:]

    @property
    def last_check(self) -> dict[str, Any]:
        return self._cache

    @property
    def incidents(self) -> list[dict[str, Any]]:
        return list(reversed(self._incidents))
