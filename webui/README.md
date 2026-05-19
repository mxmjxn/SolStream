# SolStream web installer

> **Phase 3 of the project plan — not yet implemented.**

This directory will hold the one-command web installer: a small Python app you launch via `curl | sudo bash`, which then starts a temporary HTTP server on the target host. You open it from any browser on your LAN and click through an install wizard.

## Why a web installer instead of a desktop GUI

A desktop GUI assumes the install target already has a working display server and a logged-in user — exactly the opposite of what SolStream is designed for. A web installer:

- Runs natively on a headless box
- Is administered from a separate device (your laptop's browser)
- Mirrors the UX of TrueNAS, Proxmox, OPNsense, Home Assistant, OctoPrint, etc.
- Naturally supports remote VPS / cloud installs
- Shares the same Ansible playbook as the CLI — no duplicated logic

## Planned UX

```
$ curl -fsSL https://solstream.dev/install.sh | sudo bash

SolStream web installer running at:
  http://192.168.1.20:8080

(Open that URL from any device on your network to continue.)
```

Browser flow:

1. **Welcome / hardware detection** — auto-detects GPU, kernel, distro, Secure Boot state
2. **Stream profile** — resolution, refresh, encoder preset (P4 default)
3. **Storage** — Steam library path
4. **Remote streaming (optional)** — WireGuard setup, DDNS provider
5. **Review & install** — shows generated inventory, runs the playbook with live log streaming
6. **Done** — final URL list (Sunshine, wg-easy, status page), copy buttons, "next steps" links

## Implementation plan

- **Backend:** FastAPI or Starlette (Python, lightweight)
- **Frontend:** Server-side rendered HTML + small bit of HTMX for live progress; deliberately no React/Vue bloat
- **Logs:** WebSocket streaming Ansible's stdout/stderr live
- **State:** Single JSON file under `/etc/solstream/install-state.json` — survives the installer process exiting
- **Self-bootstrapping:** the `install.sh` shim curls a tiny Python wheel, pip-installs it into a venv, runs `solstream webui` which serves on `:8080`

## Why this is a Phase 3 deliverable

Phase 1 (Ansible roles) needs to be solid first. The web installer is a UI over the playbook — if the underlying install logic is buggy, a pretty wizard makes it worse, not better. Get the install right, then layer the wizard on top.
