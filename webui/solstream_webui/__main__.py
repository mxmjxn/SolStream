"""Entrypoint: `solstream-webui` launches a local web installer."""

from __future__ import annotations

import argparse
import socket
import sys

import uvicorn

from solstream_webui.app import build_app


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog="solstream-webui",
        description="Web-based install wizard for SolStream",
    )
    p.add_argument("--port", type=int, default=8080, help="Port to listen on (default 8080)")
    p.add_argument("--host", default="0.0.0.0", help="Address to bind (default 0.0.0.0)")
    args = p.parse_args(argv)

    app = build_app()
    print(f"\n  SolStream web installer is live at:\n", flush=True)
    print(f"      http://{_lan_ip()}:{args.port}\n", flush=True)
    print("  Open that URL from any browser on your LAN to continue.\n", flush=True)

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
    return 0


def _lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    sys.exit(main())
