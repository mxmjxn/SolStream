# SolStream web installer

The one-command install path. Designed for users who don't know Ansible and don't want to.

## How it works

```
┌───────────────────┐  curl | bash   ┌──────────────────────────┐
│  User's laptop    │ ─────────────► │  Target SolStream host   │
│  (just a browser) │                │                          │
│                   │                │  install.sh:             │
│   ┌─────────────┐ │                │  • apt-get python+ansible│
│   │  Browser    │ │ ──────HTTP───► │  • git clone /opt/sol... │
│   │  192.168... │ │     :8080      │  • pip install webui     │
│   └─────────────┘ │                │  • launch solstream-webui│
└───────────────────┘                │  • serve wizard on :8080 │
                                     │                          │
                                     │  After wizard finishes:  │
                                     │  • ansible-playbook runs │
                                     │  • progress streams back │
                                     │  • final URLs displayed  │
                                     └──────────────────────────┘
```

## Why a web installer instead of a desktop GUI

A desktop GUI assumes the install target already has a working display server and a logged-in user — exactly the opposite of what SolStream is designed for. A web installer:

- Runs natively on a headless box
- Is administered from a separate device (your laptop's browser)
- Mirrors the UX of TrueNAS, Proxmox, OPNsense, Home Assistant, OctoPrint, etc.
- Naturally supports remote VPS / cloud installs
- Shares the same Ansible playbook as the CLI — no duplicated logic

## Architecture

- **Backend:** FastAPI + uvicorn (Python, lightweight)
- **Frontend:** Server-side rendered HTML with a small bit of vanilla JS for the live log stream; deliberately no React/Vue
- **Live progress:** Server-Sent Events streaming Ansible's stdout/stderr
- **Hardware detection:** runs at first page load; pre-fills sensible defaults
- **State:** in-memory per-process — the wizard is single-user and short-lived

## Files

```
webui/
├── install.sh                  # `curl | sudo bash` bootstrap
├── pyproject.toml              # Python packaging
└── solstream_webui/
    ├── __init__.py
    ├── __main__.py             # `solstream-webui` entrypoint
    ├── app.py                  # FastAPI application + routes
    ├── detect.py               # Hardware/OS/network probes
    ├── templates/
    │   ├── base.html
    │   ├── step1_welcome.html
    │   ├── step2_config.html
    │   ├── step3_review.html
    │   ├── step4_install.html
    │   └── step5_done.html
    └── static/
```

## Running locally for development

```bash
cd webui
python3 -m venv .venv
source .venv/bin/activate
pip install -e .                # install in editable mode
solstream-webui --port 8080
```

Then open `http://localhost:8080`.

## Tests

```bash
cd webui
PYTHONPATH=. python3 -m unittest discover tests/
```

## TODO

- Persist install state to `/etc/solstream/install-state.json` so a power-loss mid-install can be resumed
- Add a "skip" path for users with a pre-existing Steam install
- Sign / verify the install.sh against a public key so `curl | bash` is auditable
- Localization (English-only at v0.1)
