"""solstream CLI — thin wrapper over the Ansible playbook + diagnostics.

This is the user-facing entrypoint. Subcommands:

    solstream install [-t TAGS]  - run the install playbook
    solstream status             - show service state + URLs
    solstream urls [--json]      - print URLs only (machine-readable)
    solstream doctor             - run health checks
    solstream metrics [SECONDS]  - capture GPU/encoder metrics during a stream
    solstream version            - print version

This module is intentionally small. The real work lives in the Ansible
roles; the CLI's job is to (a) drive Ansible with sensible defaults and
(b) report on the running system's health.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

# Path discovery — the CLI may be installed via pip (data files in package)
# or run from a checkout. Find the playbook either way.
_PKG_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _PKG_DIR.parent.parent
_PLAYBOOK_CANDIDATES = [
    _REPO_ROOT / "ansible" / "solstream.yml",
    Path("/usr/local/share/solstream/ansible/solstream.yml"),
    Path("/usr/share/solstream/ansible/solstream.yml"),
]
_URLS_FILE_CANDIDATES = [
    Path("/etc/solstream/urls.json"),
]
_METRICS_SCRIPT = _PKG_DIR / "_metrics.sh"


# ─── install ────────────────────────────────────────────────────────────

def cmd_install(args: argparse.Namespace) -> int:
    """Run the install playbook against localhost (or a remote inventory)."""
    playbook = _find_first_existing(_PLAYBOOK_CANDIDATES)
    if not playbook:
        print(
            "error: could not find solstream.yml in any of:\n  "
            + "\n  ".join(str(p) for p in _PLAYBOOK_CANDIDATES),
            file=sys.stderr,
        )
        return 2

    inventory = args.inventory or (playbook.parent / "inventory" / "hosts.yml")

    if not inventory.exists() and not args.local:
        print(
            f"error: inventory file {inventory} not found.\n"
            f"  Either copy ansible/inventory/example.yml -> hosts.yml and edit,\n"
            f"  or run with --local to install on this machine.",
            file=sys.stderr,
        )
        return 2

    cmd = ["ansible-playbook"]
    if args.local:
        cmd += ["-i", "localhost,", "--connection=local"]
    else:
        cmd += ["-i", str(inventory)]
    cmd.append(str(playbook))

    if args.tags:
        cmd += ["--tags", args.tags]
    if args.skip_tags:
        cmd += ["--skip-tags", args.skip_tags]
    if args.check:
        cmd.append("--check")
    if args.verbose:
        cmd.append("-" + "v" * min(args.verbose, 4))

    print(f"running: {' '.join(cmd)}", file=sys.stderr)
    rc = subprocess.call(cmd)
    if rc == 0:
        print("\n" + "─" * 60)
        print(" SolStream install complete. Next:")
        print("─" * 60)
        cmd_urls(argparse.Namespace(json=False))
    return rc


# ─── urls ───────────────────────────────────────────────────────────────

def cmd_urls(args: argparse.Namespace) -> int:
    """Print the discoverable service URLs."""
    urls = _load_urls()
    if args.json:
        print(json.dumps(urls, indent=2))
    else:
        # Pretty
        order = ["sunshine_web_ui", "wg_easy_admin", "ssh"]
        printable = [(k, urls[k]) for k in order if k in urls]
        # Anything else
        for k, v in sorted(urls.items()):
            if k not in dict(printable):
                printable.append((k, v))
        for name, url in printable:
            label = name.replace("_", " ").title().ljust(20)
            print(f"  {label}  {url}")
    return 0


# ─── status ─────────────────────────────────────────────────────────────

def cmd_status(args: argparse.Namespace) -> int:
    """Show service status + URLs."""
    print("Services:")
    units = [
        ("gamescope-sunshine.service", "user"),
        ("seatd.service", "system"),
        ("pipewire.service", "user"),
    ]
    for unit, scope in units:
        if scope == "user":
            rc = subprocess.call(
                ["systemctl", "--user", "is-active", "--quiet", unit],
                stderr=subprocess.DEVNULL,
            )
        else:
            rc = subprocess.call(
                ["systemctl", "is-active", "--quiet", unit],
                stderr=subprocess.DEVNULL,
            )
        status = "active" if rc == 0 else "INACTIVE"
        marker = "✓" if rc == 0 else "✗"
        print(f"  {marker} {unit:35s} {status} ({scope})")
    print()
    return cmd_urls(args)


# ─── doctor ─────────────────────────────────────────────────────────────

def cmd_doctor(args: argparse.Namespace) -> int:
    """Run health checks via the doctor Ansible role."""
    playbook = _find_first_existing(_PLAYBOOK_CANDIDATES)
    if not playbook:
        print("error: doctor needs the SolStream playbook installed", file=sys.stderr)
        return 2

    cmd = [
        "ansible-playbook",
        "-i", "localhost,",
        "--connection=local",
        str(playbook),
        "--tags", "doctor",
    ]
    if args.verbose:
        cmd.append("-vvv")
    return subprocess.call(cmd)


# ─── metrics ────────────────────────────────────────────────────────────

def cmd_metrics(args: argparse.Namespace) -> int:
    """Capture GPU + encoder metrics for N seconds via the shell helper."""
    if not _METRICS_SCRIPT.exists():
        print(f"error: metrics helper not found at {_METRICS_SCRIPT}", file=sys.stderr)
        return 2

    cmd = [str(_METRICS_SCRIPT), str(args.duration)]
    print(f"capturing {args.duration}s of GPU/encoder metrics — start your stream now")
    return subprocess.call(cmd)


# ─── version ────────────────────────────────────────────────────────────

def cmd_version(args: argparse.Namespace) -> int:
    from solstream import __version__
    print(f"solstream {__version__}")
    return 0


# ─── helpers ────────────────────────────────────────────────────────────

def _find_first_existing(paths: list[Path]) -> Path | None:
    for p in paths:
        if p.exists():
            return p
    return None


def _load_urls() -> dict[str, str]:
    """Try the urls.json the discoverability role writes; fall back to defaults."""
    f = _find_first_existing(_URLS_FILE_CANDIDATES)
    if f:
        try:
            return json.loads(f.read_text())
        except Exception:
            pass
    # Fallback — detect LAN IP ourselves
    lan_ip = _detect_lan_ip()
    return {
        "sunshine_web_ui": f"https://{lan_ip}:47990",
        "wg_easy_admin": f"https://{lan_ip}:51821",
        "ssh": f"ssh {os.environ.get('USER','user')}@{lan_ip}",
        "lan_ip": lan_ip,
    }


def _detect_lan_ip() -> str:
    """Best-effort detection of the host's LAN IP."""
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


# ─── argparse setup ─────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="solstream",
        description="Headless game-streaming server installer + diagnostics",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_install = sub.add_parser("install", help="Install/update SolStream on the target host")
    p_install.add_argument("--inventory", "-i", type=Path, help="Path to Ansible inventory file")
    p_install.add_argument("--local", action="store_true",
                           help="Install on the local machine without an inventory file")
    p_install.add_argument("--tags", "-t", help="Only run these tags (comma-separated)")
    p_install.add_argument("--skip-tags", help="Skip these tags (comma-separated)")
    p_install.add_argument("--check", action="store_true", help="Dry-run only")
    p_install.add_argument("--verbose", "-v", action="count", default=0)
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
    p_metrics.add_argument("duration", type=int, default=30, nargs="?",
                           help="seconds to capture (default: 30)")
    p_metrics.set_defaults(func=cmd_metrics)

    p_version = sub.add_parser("version", help="Print version")
    p_version.set_defaults(func=cmd_version)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
