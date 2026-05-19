"""Smoke tests for the solstream CLI.

Run with:
    cd cli && PYTHONPATH=. python3 -m unittest discover tests/
"""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

PKG = Path(__file__).resolve().parent.parent / "solstream"


def _run(argv: list[str]) -> subprocess.CompletedProcess:
    cmd = [sys.executable, "-m", "solstream", *argv]
    return subprocess.run(
        cmd,
        cwd=str(PKG.parent),
        capture_output=True,
        text=True,
        timeout=30,
        env={"PYTHONPATH": str(PKG.parent), "PATH": "/usr/bin:/bin", "HOME": "/tmp"},
    )


class TestSolStreamCLI(unittest.TestCase):
    def test_version(self):
        p = _run(["version"])
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("solstream", p.stdout)

    def test_urls(self):
        p = _run(["urls"])
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("https://", p.stdout)
        self.assertIn(":47990", p.stdout)

    def test_urls_json_is_valid(self):
        p = _run(["urls", "--json"])
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads(p.stdout)
        self.assertIn("sunshine_web_ui", data)
        self.assertIn("lan_ip", data)

    def test_install_no_inventory_errors_cleanly(self):
        p = _run(["install", "--check"])
        # We don't care about the return code — just that we don't traceback
        self.assertNotIn("Traceback", p.stderr)

    def test_help_lists_subcommands(self):
        p = _run(["--help"])
        self.assertEqual(p.returncode, 0)
        for sub in ("install", "status", "urls", "doctor", "metrics", "version"):
            self.assertIn(sub, p.stdout, f"missing subcommand: {sub}")


if __name__ == "__main__":
    unittest.main()
