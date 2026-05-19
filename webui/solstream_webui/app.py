"""FastAPI app — wizard pages, ansible runner, live progress stream."""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from solstream_webui import detect

_HERE = Path(__file__).resolve().parent
_TEMPLATES = Jinja2Templates(directory=str(_HERE / "templates"))
_STATIC = _HERE / "static"


# ─── Install-state machine (in-memory; single user; resets on restart) ──

@dataclass
class InstallState:
    job_id: str
    status: str = "pending"   # pending | running | succeeded | failed
    log_buffer: list[str] = field(default_factory=list)
    process: subprocess.Popen | None = field(default=None, repr=False)


_STATE: dict[str, InstallState] = {}


# ─── App factory ─────────────────────────────────────────────────────────

def build_app() -> FastAPI:
    app = FastAPI(title="SolStream Web Installer")
    if _STATIC.exists():
        app.mount("/static", StaticFiles(directory=str(_STATIC)), name="static")

    @app.get("/", response_class=HTMLResponse)
    async def page_root(request: Request):
        ctx = {
            "request": request,
            "hardware": detect.snapshot(),
        }
        return _TEMPLATES.TemplateResponse("step1_welcome.html", ctx)

    @app.post("/config", response_class=HTMLResponse)
    async def page_config(
        request: Request,
        confirm: str = Form(...),
    ):
        if confirm != "yes":
            return _TEMPLATES.TemplateResponse(
                "step1_welcome.html",
                {"request": request, "hardware": detect.snapshot(),
                 "error": "Please confirm to continue."},
            )
        return _TEMPLATES.TemplateResponse(
            "step2_config.html",
            {"request": request, "hardware": detect.snapshot()},
        )

    @app.post("/review", response_class=HTMLResponse)
    async def page_review(
        request: Request,
        resolution: str = Form("2560x1440"),
        refresh: int = Form(120),
        steam_library: str = Form("/data/downloads/steamlibrary"),
        nvenc_preset: int = Form(4),
        enable_wireguard: bool = Form(False),
        wg_easy_password_hash: str = Form(""),
        ddns_provider: str = Form(""),
        ddns_subdomain: str = Form(""),
        ddns_token: str = Form(""),
    ):
        width, height = resolution.split("x")
        config = {
            "width": int(width),
            "height": int(height),
            "refresh": refresh,
            "steam_library": steam_library,
            "nvenc_preset": nvenc_preset,
            "enable_wireguard": enable_wireguard,
            "wg_easy_password_hash": wg_easy_password_hash,
            "ddns_provider": ddns_provider,
            "ddns_subdomain": ddns_subdomain,
            "ddns_token": ddns_token,
        }
        return _TEMPLATES.TemplateResponse(
            "step3_review.html",
            {
                "request": request,
                "hardware": detect.snapshot(),
                "config": config,
                "config_json": json.dumps(config),
            },
        )

    @app.post("/install/start")
    async def install_start(config_json: str = Form(...)) -> JSONResponse:
        config = json.loads(config_json)
        job_id = str(uuid.uuid4())[:8]
        state = InstallState(job_id=job_id, status="running")
        _STATE[job_id] = state
        asyncio.create_task(_run_install(state, config))
        return JSONResponse({"job_id": job_id})

    @app.get("/install/log/{job_id}")
    async def install_log(job_id: str) -> StreamingResponse:
        state = _STATE.get(job_id)
        if not state:
            return JSONResponse({"error": "unknown job_id"}, status_code=404)
        return StreamingResponse(_log_stream(state), media_type="text/event-stream")

    @app.get("/install/status/{job_id}")
    async def install_status(job_id: str) -> JSONResponse:
        state = _STATE.get(job_id)
        if not state:
            return JSONResponse({"error": "unknown job_id"}, status_code=404)
        return JSONResponse({"job_id": job_id, "status": state.status})

    @app.get("/install/watch", response_class=HTMLResponse)
    async def page_install_watch(request: Request):
        return _TEMPLATES.TemplateResponse(
            "step4_install.html",
            {"request": request},
        )

    @app.get("/done", response_class=HTMLResponse)
    async def page_done(request: Request):
        urls = detect.urls()
        return _TEMPLATES.TemplateResponse(
            "step5_done.html",
            {"request": request, "urls": urls},
        )

    return app


# ─── Ansible runner ─────────────────────────────────────────────────────

async def _run_install(state: InstallState, config: dict) -> None:
    """Launch ansible-playbook with the user's selections."""
    # In a real install, locate the playbook similarly to the CLI module.
    # For now, this is a placeholder that prints what it would do.
    playbook = Path("/usr/local/share/solstream/ansible/solstream.yml")
    if not playbook.exists():
        playbook = _HERE.parent.parent / "ansible" / "solstream.yml"

    extra_vars = {
        "solstream_resolution_width": config["width"],
        "solstream_resolution_height": config["height"],
        "solstream_refresh_hz": config["refresh"],
        "solstream_steam_library": config["steam_library"],
        "solstream_nvenc_preset": config["nvenc_preset"],
        "solstream_enable_wireguard": config["enable_wireguard"],
    }
    if config["enable_wireguard"]:
        extra_vars.update(
            solstream_wg_easy_password_hash=config["wg_easy_password_hash"],
            solstream_ddns_provider=config["ddns_provider"],
            solstream_ddns_subdomain=config["ddns_subdomain"],
            solstream_ddns_token=config["ddns_token"],
        )

    cmd = [
        "ansible-playbook",
        "-i", "localhost,",
        "--connection=local",
        str(playbook),
        "-e", json.dumps(extra_vars),
    ]

    state.log_buffer.append(f"$ {' '.join(cmd)}\n")
    try:
        state.process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        assert state.process.stdout
        async for line in state.process.stdout:
            state.log_buffer.append(line.decode(errors="replace"))
        rc = await state.process.wait()
        state.status = "succeeded" if rc == 0 else "failed"
        state.log_buffer.append(f"\n[install exited with code {rc}]\n")
    except FileNotFoundError:
        state.status = "failed"
        state.log_buffer.append(
            "ERROR: ansible-playbook not found on PATH. Install ansible-core first.\n"
        )
    except Exception as e:
        state.status = "failed"
        state.log_buffer.append(f"ERROR: {type(e).__name__}: {e}\n")


async def _log_stream(state: InstallState) -> AsyncIterator[bytes]:
    """Server-Sent Events stream — yields new log lines as they appear."""
    sent = 0
    while True:
        # Send any new lines
        if sent < len(state.log_buffer):
            for line in state.log_buffer[sent:]:
                yield f"data: {json.dumps({'line': line})}\n\n".encode()
            sent = len(state.log_buffer)
        if state.status in ("succeeded", "failed"):
            yield f"data: {json.dumps({'done': True, 'status': state.status})}\n\n".encode()
            break
        await asyncio.sleep(0.25)
