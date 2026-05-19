# Changelog

All notable changes to SolStream are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and SolStream aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it reaches v0.1.0.

## [Unreleased]

### Added

- Project scaffolding: README, MIT LICENSE, architecture docs, hardware-support matrix, troubleshooting reference, router-setup guide
- Ansible playbook with 10 idempotent roles:
  - `nvidia-driver` — Secure-Boot-aware driver branch selection
  - `kernel-modeset` — synthetic EDID generation, GRUB cmdline merge, initramfs regeneration
  - `gamescope-build` — wayland 1.23 + gamescope 3.16.23 source builds with patched WSI dialog + i686 WSI cross-compile
  - `steam` — i386 multiarch + i386 NVIDIA libs + steam-installer + library dir
  - `sunshine` — pinned release `.deb` install + seatd + tuned config templates
  - `pipewire-session` — user PipeWire + WirePlumber + pulseaudio-utils
  - `session-wrapper` — `solstream-session.sh` + user systemd unit
  - `wireguard` — wg-easy + DuckDNS Docker containers (opt-in)
  - `discoverability` — MOTD + `/etc/solstream/urls.json`
  - `doctor` — green/red health-check matrix mapped to troubleshooting docs
- `solstream` CLI with `install`, `status`, `urls`, `doctor`, `metrics`, `version` subcommands
- Web installer (`solstream-webui`) with 5-step wizard, hardware detection, SSE-streamed live install progress
- `webui/install.sh` one-command bootstrap (`curl | sudo bash`)
- Vagrant test environment for non-GPU integration testing
- CI workflows: ansible-lint, ruff, markdown-link-check, CLI unittest, webui unittest, EDID multi-resolution validation, ansible syntax-check, install.sh syntax-check
- Patches directory holding the gamescope WSI dialog-suppress patch

### Known limitations

- v0.1 supports Ubuntu 24.04 + NVIDIA Ampere/Ada only. Other targets are planned.
- Windows host support is design-doc only — `windows/` directory has scope, no code yet.
- GPU-passthrough testing in CI isn't possible on the free GitHub Actions tier; we test apt resolution + playbook syntax + EDID generation, but not driver loading + actual streaming.
- The web installer is single-user / single-job — no persistence across restarts.
