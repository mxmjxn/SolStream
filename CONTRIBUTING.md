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

## Cutting a release

(Maintainer reference; contributors don't normally need this.)

The release pipeline is automated:

1. **As PRs land on `main`** — `.github/workflows/release.yml` runs the `draft-notes` job which keeps a draft release at the top of the [Releases page](https://github.com/mxmjxn/SolStream/releases) with auto-categorized notes based on PR labels (see `.github/release-drafter.yml`).
2. **To cut a release** — tag and push. The tag's suffix determines which platform the release is for:

   | Tag pattern | Platform | Pre-release? |
   |---|---|---|
   | `v0.2.0` | Linux (default) | No |
   | `v0.2.0-linux` | Linux (explicit) | No |
   | `v0.2.0-windows` | Windows | No |
   | `v0.2.0-rc1` | Linux | Yes (`-rc` in tag) |
   | `v0.2.0-windows-rc1` | Windows | Yes |
   | `v0.2.0-beta1` / `v0.2.0-alpha1` | Linux | Yes |

   ```bash
   # Linux stable
   git tag -a v0.2.0 -m "v0.2.0 — what's new"
   git push origin v0.2.0

   # Windows stable
   git tag -a v0.2.0-windows -m "v0.2.0 (Windows) — what's new"
   git push origin v0.2.0-windows

   # Linux pre-release
   git tag -a v0.2.0-rc1 -m "v0.2.0-rc1 — what's new"
   git push origin v0.2.0-rc1
   ```

3. The `publish` job in `release.yml` triggers on the `v*` tag, detects the platform from the suffix, prepends a `(Linux)` or `(Windows)` label to the release title, extracts the matching section from `CHANGELOG.md` (or auto-generates if no section exists), and publishes a real Release with the `prerelease` flag set automatically based on the tag pattern (`-rc`, `-beta`, `-alpha` → pre-release). The two platforms have independent release cadences — a Linux v0.3.0 doesn't imply a Windows v0.3.0 exists.

When labeling PRs that should appear in release notes, use these labels (from `.github/release-drafter.yml`):

- `breaking-change`, `enhancement`, `feature`, `role`, `bug`, `fix`, `windows`, `documentation`, `hardware`, `chore`, `ci`, `dependencies`

Add `skip-changelog` to suppress a PR from notes (e.g., for trivial cleanups).
