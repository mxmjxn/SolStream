"""Hardware / OS / network detection — used to pre-fill the wizard."""

from __future__ import annotations

import json
import platform
import socket
import subprocess
from pathlib import Path
from typing import Any


def snapshot() -> dict[str, Any]:
    """Return everything the wizard wants to show on its first page."""
    return {
        "hostname": socket.gethostname(),
        "lan_ip": _lan_ip(),
        "os": _os_release(),
        "kernel": platform.release(),
        "gpu": _detect_gpu(),
        "secure_boot": _detect_secure_boot(),
        "cpu": _detect_cpu(),
        "memory_gb": _detect_memory_gb(),
        "disks": _detect_disks(),
    }


def urls() -> dict[str, str]:
    """Final URLs shown after install."""
    p = Path("/etc/solstream/urls.json")
    if p.exists():
        try:
            return json.loads(p.read_text())
        except Exception:
            pass
    ip = _lan_ip()
    return {
        "sunshine_web_ui": f"https://{ip}:47990",
        "wg_easy_admin": f"https://{ip}:51821",
        "ssh": f"ssh user@{ip}",
        "lan_ip": ip,
    }


# ─── helpers ────────────────────────────────────────────────────────────

def _lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def _os_release() -> str:
    try:
        with open("/etc/os-release") as f:
            data = dict(line.strip().split("=", 1) for line in f if "=" in line)
        return data.get("PRETTY_NAME", "").strip('"')
    except OSError:
        return platform.platform()


def _detect_gpu() -> dict[str, str]:
    """Returns vendor + model summary. Best-effort, never raises."""
    try:
        out = subprocess.check_output(
            ["lspci", "-nn"], stderr=subprocess.DEVNULL, text=True, timeout=2,
        )
        for line in out.splitlines():
            if "VGA" in line or "3D" in line:
                vendor = "Unknown"
                if "NVIDIA" in line:
                    vendor = "NVIDIA"
                elif "AMD" in line or "ATI" in line:
                    vendor = "AMD"
                elif "Intel" in line:
                    vendor = "Intel"
                # Extract model
                model = line.split(": ", 1)[-1]
                return {"vendor": vendor, "model": model}
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return {"vendor": "unknown", "model": "unknown"}


def _detect_secure_boot() -> str:
    try:
        out = subprocess.check_output(
            ["mokutil", "--sb-state"], stderr=subprocess.DEVNULL, text=True, timeout=2,
        )
        return "enabled" if "enabled" in out.lower() else "disabled"
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return "unknown"


def _detect_cpu() -> str:
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def _detect_memory_gb() -> float:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    kb = int(line.split()[1])
                    return round(kb / 1024 / 1024, 1)
    except OSError:
        pass
    return 0.0


def _detect_disks() -> list[dict[str, str]]:
    try:
        out = subprocess.check_output(
            ["df", "-h", "--output=target,size,avail"],
            stderr=subprocess.DEVNULL, text=True, timeout=2,
        )
        lines = out.strip().splitlines()[1:]
        disks: list[dict[str, str]] = []
        for line in lines:
            parts = line.split()
            if len(parts) >= 3 and parts[0].startswith("/data"):
                disks.append({"mount": parts[0], "size": parts[1], "avail": parts[2]})
        return disks
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return []
