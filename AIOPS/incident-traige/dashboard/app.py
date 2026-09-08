"""Incident Triage Dashboard - FastAPI application."""

from __future__ import annotations

import asyncio
import logging
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from ai_triage import AITriage
from chaos import ChaosInjector
from health_monitor import HealthMonitor
from k8s_collector import K8sCollector, SERVICES
from remediator import Remediator

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent
USE_LOCAL = os.getenv("USE_LOCAL_URLS", "false").lower() == "true"

health_monitor = HealthMonitor(use_local=USE_LOCAL)
k8s = K8sCollector()
ai_triage = AITriage()
chaos = ChaosInjector()
remediator = Remediator()
last_triage: dict = {}
last_fix: dict = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    async def poll_health():
        while True:
            try:
                await health_monitor.check_all()
            except Exception:
                logger.exception("Health poll failed")
            await asyncio.sleep(8)

    task = asyncio.create_task(poll_health())
    yield
    task.cancel()


app = FastAPI(title="Incident Triage Dashboard", lifespan=lifespan)
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))
app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")


def _k8s_context() -> dict:
    ctx = {"deployments": {}, "pods": {}, "events": {}}
    for name, meta in SERVICES.items():
        if name == "postgres":
            dep_name = "postgres"
        else:
            dep_name = meta["deployment"]
        ctx["deployments"][name] = k8s.get_deployment_status(dep_name)
        ctx["pods"][name] = k8s.get_pod_info(dep_name)
        ctx["events"][name] = k8s.get_events(dep_name)
    return ctx


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    health = health_monitor.last_check or await health_monitor.check_all()
    k8s_ctx = _k8s_context()
    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "health": health,
            "k8s": k8s_ctx,
            "incidents": health_monitor.incidents,
            "injections": chaos.injections,
            "active_injections": chaos.active,
            "ai_available": ai_triage.available,
            "last_triage": last_triage,
            "last_fix": last_fix,
        },
    )


@app.get("/health")
async def health():
    return {"status": "ok", "service": "triage-dashboard"}


@app.get("/api/health")
async def api_health():
    return await health_monitor.check_all()


@app.get("/api/k8s")
async def api_k8s():
    return _k8s_context()


def _build_triage_context() -> dict:
    health = health_monitor.last_check
    k8s_ctx = _k8s_context()
    logs = {}
    for name in ["catalog-service", "orders-service", "inventory-service"]:
        logs[name] = k8s.get_pod_logs(name, tail_lines=60)
    return {
        "health": health,
        "deployments": k8s_ctx["deployments"],
        "pods": k8s_ctx["pods"],
        "events": k8s_ctx["events"],
        "logs": logs,
        "active_injections": chaos.active,
    }


async def _run_triage_analysis() -> dict:
    global last_triage
    health = await health_monitor.check_all()
    context = _build_triage_context()
    context["health"] = health
    last_triage = await ai_triage.analyze(context)
    if not last_triage.get("remediation_actions"):
        last_triage["remediation_actions"] = remediator.build_actions_from_context(context)
    last_triage["timestamp"] = time.time()
    return last_triage


@app.post("/api/triage")
async def run_triage():
    return await _run_triage_analysis()


@app.post("/api/triage/fix")
async def triage_and_fix():
    global last_fix
    triage = await _run_triage_analysis()
    actions = triage.get("remediation_actions", [])
    if not actions:
        last_fix = {"status": "nothing_to_do", "message": "No automated actions available"}
        return last_fix

    last_fix = remediator.execute_plan(actions)
    await asyncio.sleep(12)
    health = await health_monitor.check_all()
    last_fix["health_after"] = health.get("overall")
    last_fix["triage"] = triage
    return last_fix


@app.post("/api/remediate/ai-fix")
async def apply_ai_fix():
    global last_fix
    actions = last_triage.get("remediation_actions", [])
    if not actions:
        return JSONResponse({"error": "Run AI Triage first — no actions to apply"})
    last_fix = remediator.execute_plan(actions)
    await asyncio.sleep(12)
    health = await health_monitor.check_all()
    last_fix["health_after"] = health.get("overall")
    return JSONResponse(last_fix)


@app.post("/api/chaos/inject")
async def inject_failure(injection_id: str = Form(...)):
    result = chaos.inject(injection_id)
    await health_monitor.check_all()
    return JSONResponse(result)


@app.post("/api/chaos/reset")
async def reset_chaos():
    result = chaos.reset_all()
    await health_monitor.check_all()
    return JSONResponse(result)


@app.post("/api/remediate/apply")
async def apply_remediation(action: str = Form(...), deployment: str = Form(...)):
    if action == "restart":
        result = k8s.restart_deployment(deployment)
    elif action == "reset_env":
        result = chaos.reset_service(deployment)
    elif action == "scale_up":
        result = k8s.scale_deployment(deployment, 1)
    else:
        result = {"error": f"Unknown action: {action}"}
    await health_monitor.check_all()
    return JSONResponse(result)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app:app", host="0.0.0.0", port=8080, reload=False)
