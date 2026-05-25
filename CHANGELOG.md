# Changelog

All notable changes to SolStream are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and SolStream aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it reaches v0.1.0.

## [Unreleased]

### Added

- **"Quit current game" Sunshine tile + `solstream-game-shutdown.sh` script.** Tile appears in the Moonlight app grid alongside "Steam Big Picture." Selecting it finds the running game's reaper process, sends SIGTERM, waits 8 seconds, then SIGKILLs if needed. Steam Big Picture itself stays up. Primarily for mobile clients where the on-screen gamepad makes quitting from inside the game painful. Log at `/tmp/solstream-game-shutdown.log`.

## [0.1.0-windows-rc1] — Windows scaffolding release

First release of the Windows track. This is a **scaffolding-level release** — the install scripts have been written, syntax-checked in CI, and are theoretically correct based on the Linux deployment and Sunshine's Windows documentation, but **have not been exercised on real Windows hardware yet**. Use at your own risk; contributions reporting what breaks are extremely welcome.

### What's in the box

- **`windows/scripts/Install-SolStream.ps1`** — PowerShell installer. As Administrator on a Windows 11 host with NVIDIA GPU:
  - Detects NVIDIA GPU via WMI; refuses on non-NVIDIA hosts
  - Installs Sunshine via `winget install LizardByte.Sunshine`, falls back to direct `.msi` download if winget unavailable
  - Drops a tuned `sunshine.conf` + `apps.json` at `%APPDATA%\Sunshine\` with the same low-latency NVENC profile the Linux track uses (P4 preset, two-pass off, realtime_hags on)
  - Adds Windows Firewall rules for Sunshine's TCP/UDP ports
  - Optionally installs WireGuard for Windows via winget
  - Starts the SunshineService and prints next-step URLs

- **`windows/scripts/Test-SolStream.ps1`** — Windows equivalent of `solstream doctor`:
  - Checks NVIDIA GPU + driver version, Sunshine binary + service, config files, listening ports, firewall rules
  - Prints green/red summary, exits with count of failures

### Why the Windows track is small

About 80% of what makes the Linux installer complex doesn't apply on Windows. Windows ships native equivalents for everything that hurt on Linux:

| Linux problem | Windows status |
|---|---|
| gamescope compositor | Native DWM, not needed |
| Synthetic EDID + DRM modeset | Sunshine has a [Virtual Display Driver](https://github.com/itsmikethetech/Virtual-Display-Driver) |
| NVIDIA driver branch / DKMS / Secure Boot | One installer from nvidia.com, signed |
| seatd / libseat for DRM-master | N/A — Windows GPU access is unprivileged |
| PipeWire null-sink | Sunshine has WASAPI null sink built-in |
| Steam first-run zenity bootstrap | Steam's Windows installer is a normal .msi |
| systemd user units | Windows Service / Task Scheduler |
| Cross-compiled i686 WSI Vulkan layer | N/A — DXGI, not Vulkan |

What's left to automate is mostly: firewall rules, Sunshine + WireGuard install commands, and dropping the tuned config templates. Everything in `Install-SolStream.ps1`.

### Installing

```powershell
git clone https://github.com/mxmjxn/SolStream.git C:\SolStream
cd C:\SolStream\windows\scripts
Set-ExecutionPolicy -Scope Process Bypass
.\Install-SolStream.ps1
.\Test-SolStream.ps1     # verify
```

### Known gaps

1. **No real-hardware testing has been done.** The scripts pass PSScriptAnalyzer in CI and parse cleanly, but no one has confirmed they actually do the right thing on a Windows 11 box yet.
2. **Virtual Display Driver install is not automated.** The installer leaves a `Write-Warn` pointing at the manual install link.
3. **Steam Big Picture path is hardcoded** to `C:\Program Files (x86)\Steam\Steam.exe`. Users who installed Steam elsewhere will need to edit `apps.json` manually.
4. **No winget manifest exists yet.** Long-term plan is to publish `winget install LizardByte.SolStream`. See `windows/winget-manifest/README.md`.
5. **No web installer for Windows.** The Python webui is OS-agnostic in principle, but no Windows bootstrap script (PowerShell equivalent of `install.sh`) exists yet.

### Contributing

If you have a Windows 11 machine with an NVIDIA GPU and an hour, opening a PR with whatever you found broken would be the single most valuable contribution to SolStream right now. Use the [hardware report template](https://github.com/mxmjxn/SolStream/issues/new?template=hardware_report.yml).

## [0.1.0] — Unreleased (v0.1 release candidate)

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

### Project-meta

- CONTRIBUTING.md with role conventions, coding style, and reporting templates
- SECURITY.md with disclosure policy and threat model
- GitHub issue templates: bug_report.yml, feature_request.yml, hardware_report.yml
- GitHub PR template
- .github/FUNDING.yml placeholder
- README status badges for lint + integration CI

### Known limitations

- v0.1 supports Ubuntu 24.04 + NVIDIA Ampere/Ada only on Linux. Other targets are planned.
- Windows host support is scaffolding-level (working PowerShell installer + doctor, no real-hardware testing yet).
- GPU-passthrough testing in CI isn't possible on the free GitHub Actions tier; we test apt resolution + playbook syntax + EDID generation, but not driver loading + actual streaming.
- The web installer is single-user / single-job — no persistence across restarts.
