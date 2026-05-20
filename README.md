# SolStream

[![Lint](https://github.com/mxmjxn/SolStream/actions/workflows/lint.yml/badge.svg)](https://github.com/mxmjxn/SolStream/actions/workflows/lint.yml)
[![Integration](https://github.com/mxmjxn/SolStream/actions/workflows/integration.yml/badge.svg)](https://github.com/mxmjxn/SolStream/actions/workflows/integration.yml)
[![Latest Release](https://img.shields.io/github/v/release/mxmjxn/SolStream?include_prereleases&sort=semver)](https://github.com/mxmjxn/SolStream/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Headless game-streaming server, on a fresh Ubuntu install, in about 15 minutes.

SolStream turns a Linux box with an NVIDIA GPU into a Steam Big Picture host you stream to phones, tablets, TVs, and other PCs over LAN or the open internet — via [Sunshine](https://github.com/LizardByte/Sunshine) (host) and [Moonlight](https://moonlight-stream.org/) (clients).

The pieces under the hood already exist — gamescope, Sunshine, Steam, PipeWire, WireGuard. Wiring them together correctly on a headless box is a multi-day exercise involving Secure-Boot quirks, kernel-module signing, synthetic EDIDs, custom Vulkan layer builds, ISP-side filters, and a dozen other foot-guns most documentation skips. SolStream encodes the answer to every one of them in a single, idempotent installer.

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Moonlight client (anywhere)  ──── HEVC over IP/WireGuard ───┐     │
│                                                              │     │
│                                                  ┌───────────▼───┐ │
│                                                  │   Sunshine    │ │
│                                                  └───────▲───────┘ │
│                                                          │ KMS     │
│                                                  ┌───────┴───────┐ │
│                                                  │   gamescope   │ │
│                                                  └───────▲───────┘ │
│                                                          │         │
│                                                  ┌───────┴───────┐ │
│                                                  │  Steam (BPM)  │ │
│                                                  └───────────────┘ │
│                                                                     │
│                       SolStream Linux host                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Status

🚧 **Pre-release.** Pulled from a real (private) production deployment's notes and packaged into an idempotent installer. Public API will stabilize at v0.1.0.

## Why this exists

The standard "how to stream PC games to your TV" article on the internet assumes you have a monitor attached, an Xfce desktop, an X11 session, a powered-up account in a logind seat, and an ISP that doesn't actively block WireGuard traffic. Real headless servers have none of those. SolStream is what happens when you actually try to build the thing in a closet rack and write down everything that breaks.

The full list of foot-guns documented and pre-solved is in [`docs/troubleshooting.md`](docs/troubleshooting.md). A short selection:

- NVIDIA driver branch / Secure Boot / DKMS-vs-signed-modules interactions
- Synthetic EDID injection so gamescope's DRM backend has a CRTC to drive on a fully headless box
- gamescope's external Wayland socket missing `xdg_output_manager_v1` (forces the EDID + KMS path over the wlr-screencopy path)
- `seatd` needed for DRM-master without a logind session
- Cross-compiling the i686 gamescope WSI Vulkan layer (gamescope ships only x86_64)
- `VK_LAYER_NV_optimus` interfering with WSI hooks on desktops
- gamescope WSI dialog popups under Proton/DXVK on stock builds (patched out)
- Steam's first-run `zenity` install prompt on a TTY-only box (auto-accepted)
- PipeWire null-sink for Sunshine audio capture (and remembering you need `pulseaudio-utils` for `pactl`)
- ISP-side malicious-site filters (e.g., Comcast xFi / Lionic) that silently TLS-reject DuckDNS

## Quickstart

> One of these. Pick the one that matches your comfort level.

### 🎯 Quickstart A — One command (recommended for new users)

```bash
curl -fsSL https://raw.githubusercontent.com/mxmjxn/SolStream/main/webui/install.sh | sudo bash
```

The bootstrap script installs minimal apt dependencies, clones the repo to `/opt/solstream`, sets up a Python venv, then launches the web installer on port `8080`. Open `http://<your-host-ip>:8080` from any browser on your LAN, click through the wizard, and the install runs while you watch. ~10 minutes on a typical box.

### Quickstart B — CLI (for power users / scripting)

```bash
pip install solstream
sudo solstream install
```

### Quickstart C — Ansible (for fleets or homelab admins)

```bash
git clone https://github.com/mxmjxn/SolStream.git
cd SolStream/ansible
cp inventory/example.yml inventory/hosts.yml   # edit hosts
ansible-playbook -i inventory/hosts.yml solstream.yml
```

## Supported hardware

See [`docs/hardware-support.md`](docs/hardware-support.md) for the live matrix. Short version for v0.1:

- **OS**: Ubuntu 24.04 LTS (Debian 13, Pop_OS later)
- **GPU**: NVIDIA Ampere/Ada (RTX 30/40 series) with open kernel modules
- **CPU**: any modern x86_64; 4+ cores recommended for encoding headroom
- **Network**: wired Ethernet preferred for the host
- **Clients**: any Moonlight client (PC, Shield TV, iOS, Android, Apple TV)

## What's planned but not yet shipped

- **Windows host installer** — Sunshine itself runs natively on Windows; about 80% of what makes Linux hard (gamescope, EDID, DKMS, etc.) is unnecessary there. A PowerShell + winget track is on the roadmap. For now, the [LizardByte Sunshine Windows installer](https://github.com/LizardByte/Sunshine/releases) plus our `sunshine.conf` templates in `files/sunshine-templates/` is the recommended path.
- **AMD GPU support** — Sunshine + VAAPI works on AMD, but the driver/kernel paths differ. Separate role pending.
- **Multi-host orchestration** — a single SolStream "controller" managing many streaming hosts. Not v1 scope.

## Project structure

```
ansible/      # Idempotent Ansible roles, the actual install logic
cli/          # Python CLI wrapper around the playbook
webui/        # The one-command web installer
windows/      # PowerShell + winget installer (planned)
docs/         # Architecture, hardware matrix, troubleshooting, router setup
patches/      # Source patches we apply to upstream (e.g. gamescope WSI dialog)
files/        # Static artifacts (EDID generator, Vulkan layer manifests, systemd units)
tests/        # Vagrant boxes + CI scripts
```

## Contributing

PRs welcome. Especially valuable:

- New OS targets (Debian 13, Pop_OS, Bazzite host mode)
- AMD GPU role
- Windows installer scripts
- Documentation translations
- Test deployments on hardware we don't have

See [`docs/architecture.md`](docs/architecture.md) before opening a feature PR — there's some structure to the way roles interact.

## License

MIT. See [`LICENSE`](LICENSE).

## Acknowledgements

Stands on the shoulders of:

- [Sunshine](https://github.com/LizardByte/Sunshine) by LizardByte
- [Moonlight](https://github.com/moonlight-stream)
- [gamescope](https://github.com/ValveSoftware/gamescope) by Valve
- [wg-easy](https://github.com/wg-easy/wg-easy)

Plus inspiration from [Bazzite](https://bazzite.gg/), [HoloISO](https://github.com/HoloISO/holoiso), and Valve's SteamOS, which solve adjacent problems beautifully on their own terms.
