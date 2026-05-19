# Contributing to SolStream

Thanks for considering a contribution. SolStream is a single-maintainer project right now, and PRs are very welcome.

## What's most valuable

In rough priority order:

1. **Testing on hardware we don't have** — different NVIDIA GPUs (especially 40/50 series), different motherboards, different Ubuntu point releases. Bug reports with `solstream doctor --verbose` output are gold.
2. **AMD GPU support** — Sunshine + VAAPI works; a new `amd-driver` Ansible role (parallel to `nvidia-driver`) is mostly a translation exercise.
3. **Windows installer maturity** — the PowerShell scripts in `windows/scripts/` are scaffolding; they need real testing.
4. **Additional OS targets** — Debian 13, Pop_OS, NixOS, Bazzite host mode.
5. **Documentation translations** — currently English-only.
6. **New troubleshooting entries** — if you hit something not in `docs/troubleshooting.md`, the PR to add it has high impact.

## Before opening a PR

- Read [`docs/architecture.md`](docs/architecture.md) — the role-interaction model has structure you'll want to respect.
- For new Ansible roles, follow the pattern in `nvidia-driver` and `session-wrapper`:
  - `defaults/main.yml` for tunable variables
  - `tasks/main.yml` idempotent
  - `templates/` for config files (use `{{ ansible_managed }}` at the top)
  - `handlers/main.yml` for side effects
  - `meta/main.yml` declaring dependencies
- Run the CLI tests: `cd cli && PYTHONPATH=. python3 -m unittest discover tests/`
- Run the webui detect tests: `cd webui && PYTHONPATH=. python3 -m unittest discover tests/`
- Add troubleshooting entries for new failure modes you discover.

## Coding conventions

### Ansible

- `ansible.builtin.*` over bare module names
- Tag every task with a meaningful role-level tag
- `become: true` only where root is actually needed
- Avoid `shell:` if `command:` works; avoid `command:` if a dedicated module exists
- Idempotency: every task should be safe to re-run

### Python (CLI + webui)

- Type hints with `from __future__ import annotations`
- No third-party deps in the CLI core beyond ansible-core
- Web UI deps live only in webui/ — keep the CLI installable without them
- Unittest for tests (not pytest) — keeps the dep tree minimal

### Shell

- `set -euo pipefail` at the top
- Quote everything
- Long lines: backslash-continued, not collapsed

### Commits

- Imperative mood: "Add foo" not "Added foo"
- First line: ≤72 chars
- Wrap body at ~80 chars
- Reference issues if relevant

## Reporting bugs

Open an issue with:

```
Output of: `solstream doctor --verbose`
Output of: `uname -a; lsb_release -a; nvidia-smi`
Output of: `journalctl --user -u gamescope-sunshine.service --since '1 hour ago'`
Symptom description: what you expected, what actually happened
```

## Security

If you find a security issue (especially in `install.sh`, the webui, or anything that runs as root), please email maxim.jackson@live.com instead of opening a public issue. See [`SECURITY.md`](SECURITY.md).
