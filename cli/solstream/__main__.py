"""solstream CLI — thin wrapper over the Ansible playbook + diagnostics.

This is the user-facing entrypoint. Subcommands:

    solstream install     - run the install playbook (interactive)
    solstream status      - show service state + key URLs
    solstream urls        - print URLs only (machine-readable)
    solstream doctor      - run health checks, report green/red status
    solstream metrics N   - capture N seconds of GPU/encoder metrics

This module is intentionally small. The real work lives in the Ansible
roles; the CLI's job is to (a) drive Ansible with sensible defaults and
(b) check the resulting system's health.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def cmd_install(args: argparse.Namespace) -> int:
    """Run the install playbook against localhost (or a remote inventory)."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    playbook = repo_root / "ansible" / "solstream.yml"
    inventory = args.inventory or (repo_root / "ansible" / "inventory" / "hosts.yml")

    if not playbook.exists():
        print(f"error: {playbook} not found", file=sys.stderr)
        return 2

    cmd = [
        "ansible-playbook",
        "-i", str(inventory),
        str(playbook),
    ]
    if args.tags:
        cmd += ["--tags", args.tags]
    if args.check:
        cmd.append("--check")

    print(f"running: {' '.join(cmd)}")
    return subprocess.call(cmd)


def cmd_urls(args: argparse.Namespace) -> int:
    """Print the discoverable service URLs."""
    # TODO: read from /etc/solstream/urls.json once discoverability role writes it
    lan_ip = _detect_lan_ip()
    urls = {
        "sunshine_web_ui": f"https://{lan_ip}:47990",
        "wg_easy_admin": f"https://{lan_ip}:51821",
    }
    if args.json:
        print(json.dumps(urls, indent=2))
    else:
        for name, url in urls.items():
            print(f"{name:18s}  {url}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Show service status + URLs."""
    print("Services:")
    for unit in ("gamescope-sunshine.service",):
        rc = subprocess.call(
            ["systemctl", "--user", "is-active", "--quiet", unit]
        )
        print(f"  {unit:35s} {'active' if rc == 0 else 'INACTIVE'}")
    print()
    return cmd_urls(args)


def cmd_doctor(args: argparse.Namespace) -> int:
    """Run health checks and report status."""
    # TODO: shell out to `ansible-playbook --tags doctor` once that role exists
    print("solstream doctor — TODO, run via 'ansible-playbook --tags doctor' for now")
    return 0


def cmd_metrics(args: argparse.Namespace) -> int:
    """Capture GPU + encoder metrics for N seconds."""
    # TODO: port capture-stream-metrics.sh into Python or shell out
    print(f"solstream metrics — TODO ({args.duration}s capture)")
    return 0


def _detect_lan_ip() -> str:
    """Best-effort detection of the host's LAN IP."""
    # Open a UDP socket to a public address — kernel picks the right interface
    import socket

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="solstream",
        description="Headless game-streaming server installer + diagnostics",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_install = sub.add_parser("install", help="Install/update SolStream on the target host")
    p_install.add_argument("--inventory", "-i", type=Path, help="Path to Ansible inventory file")
    p_install.add_argument("--tags", "-t", help="Only run these tags (comma-separated)")
    p_install.add_argument("--check", action="store_true", help="Dry-run only")
    p_install.set_defaults(func=cmd_install)

    p_status = sub.add_parser("status", help="Show service status + URLs")
    p_status.add_argument("--json", action="store_true")
    p_status.set_defaults(func=cmd_status)

    p_urls = sub.add_parser("urls", help="Print service URLs")
    p_urls.add_argument("--json", action="store_true")
    p_urls.set_defaults(func=cmd_urls)

    p_doctor = sub.add_parser("doctor", help="Run health checks")
    p_doctor.add_argument("--verbose", "-v", action="store_true")
    p_doctor.set_defaults(func=cmd_doctor)

    p_metrics = sub.add_parser("metrics", help="Capture GPU/encoder metrics")
    p_metrics.add_argument("duration", type=int, default=30, nargs="?", help="seconds to capture")
    p_metrics.set_defaults(func=cmd_metrics)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
