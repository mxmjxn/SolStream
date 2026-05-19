# SolStream architecture

This doc explains how the pieces fit together — useful both for understanding what the installer is doing and for contributing.

## Big picture

```
                                  ┌─────────────────┐
                                  │ Remote client   │
                                  │ (phone, laptop) │
                                  └────────┬────────┘
                                           │ Moonlight
                       (LAN: direct)       │      (WAN: through WireGuard)
                                ┌──────────┴──────────┐
                                ▼                     ▼
                          ┌─────────┐         ┌──────────────┐
                          │ Router  │         │ Router NAT + │
                          │ (LAN)   │         │  WG endpoint │
                          └────┬────┘         └──────┬───────┘
                               │                     │
                               └──────────┬──────────┘
                                          ▼
                          ┌───────────────────────────────┐
                          │       SolStream Host          │
                          │                               │
                          │  Sunshine (NVENC capture)     │ ◄── pairing UI :47990
                          │  └─ captures KMS framebuffer  │
                          │                               │
                          │  gamescope (DRM backend)      │ ◄── owns DP-1 via seatd
                          │  └─ owns DP-1 ──┐             │
                          │                 │             │
                          │  ┌──────────────┘             │
                          │  ▼                            │
                          │  Steam Big Picture (BPM)      │
                          │  ├─ Xwayland inside gamescope │
                          │  ├─ NVENC + DXVK for games    │
                          │  └─ Library on /data/...      │
                          │                               │
                          │  PipeWire (user session)      │
                          │  └─ null sink → Sunshine cap  │
                          │                               │
                          │  Synthetic EDID at boot       │
                          │  └─ NVIDIA-DRM sees "monitor" │
                          │                               │
                          └───────────────────────────────┘
```

## The headless display chicken-and-egg

This is the central problem SolStream solves, and it's worth understanding before reading any role.

NVIDIA's KMS driver only enumerates connectors that report `connected` status — i.e., a real monitor advertising EDID. On a fully headless box (no physical display), every connector is `disconnected`, so no DRM CRTC ever exists. gamescope's `--backend drm` needs a CRTC. Sunshine's KMS capture path needs a CRTC. NVENC needs an output surface bound to one. Nothing works.

The official workaround in some communities is "buy an HDMI dummy plug." That's a hardware fix; we want software-only. The synthetic-EDID approach pretends a monitor is plugged in:

1. Generate a valid 1440p120 EDID block (CVT-RB timing, sane chromaticity, valid checksum).
2. Drop it at `/lib/firmware/edid/headless-1440p120.bin`.
3. Tell the kernel about it via `drm.edid_firmware=DP-1:edid/headless-1440p120.bin video=DP-1:e` on the GRUB cmdline. The `video=` part forces the connector enabled even though no real monitor is asserting hot-plug.
4. Regenerate initramfs so the firmware loader has the EDID available early enough.
5. After reboot, `/sys/class/drm/card0-DP-1/status` reports `connected`, modes include `2560x1440`, and the rest of the stack (gamescope, Sunshine, NVENC) sees a normal display.

The `files/edid/make_edid.py` script in this repo is the EDID generator. It produces valid output that passes `edid-decode` validation.

## Driver branch / Secure Boot / signed-vs-DKMS decision

The NVIDIA driver on Ubuntu 24.04 has several variants:

- `nvidia-driver-580` — proprietary kernel modules, DKMS-built
- `nvidia-driver-580-open` — open kernel modules (Ampere+ only), DKMS-built
- `nvidia-headless-no-dkms-580-server-open` — server branch, signed precompiled modules
- `linux-modules-nvidia-580-open-<kernel>-generic` — Canonical-signed precompiled modules for the desktop branch

DKMS builds modules locally with your DKMS key, which is unsigned unless you've enrolled a MOK. **On a Secure Boot system, unsigned kernel modules are rejected at load time** — meaning the NVIDIA driver silently fails to load on the next boot. This is invisible until the user tries to use the GPU and sees `nvidia-smi` errors.

SolStream's `nvidia-driver` role:

1. Detects Secure Boot state (`mokutil --sb-state`).
2. If SB is on → installs **`linux-modules-nvidia-580-open-<kernel>-generic`** (Canonical-signed precompiled) and explicitly avoids DKMS.
3. If SB is off → either path works; we pick DKMS for newer-kernel agility.
4. Records which choice was made so `solstream doctor` can verify the right modules are loaded.

This catches the most common "I rebooted and now the GPU doesn't work" failure mode.

## Why gamescope is necessary even with a virtual display

If we've already faked a 1440p120 monitor with EDID, why bother with gamescope? Why not just have Sunshine capture the raw KMS framebuffer that... nothing's drawing to?

Because *something has to render*. The synthetic display has no compositor by default. Without gamescope:

- No window manager → Steam Big Picture has nowhere to draw
- No frame pacing → presented frames don't align with NVENC's encode tick
- No scaler → can't downscale on the host if a client wants 1080p from a 1440p source
- No HDR tonemap, no FSR/NIS upscaling, no integer-scale option for retro games
- No way to switch resolution per-game without reconfiguring DRM

gamescope is the micro-compositor that gives the stack all of those. It:
- Owns the DRM device via `seatd`
- Renders into the DP-1 framebuffer (which Sunshine then captures)
- Hosts Xwayland so X11 games (Steam itself, the majority of older titles) work
- Forwards inputs from Sunshine's virtual gamepad to the focused window

## The `seatd` requirement

gamescope's `--backend drm` requires DRM-master access. On a desktop you get this automatically because you're logged into a graphical session managed by `systemd-logind`. On a headless server with only SSH, there's no logind seat for your user — and the bundled libseat fallback ("builtin") tries to open `/dev/tty0` for VT switching, which requires `tty` group membership and a real VT. Neither exists on a TTY-less remote box.

`seatd` runs as a system service, opens `/dev/dri/card0` as root, and brokers FD access to clients via a Unix socket guarded by group membership (`video` on Ubuntu). gamescope's libseat then connects to `seatd` and gets the DRM-master FD without ever needing logind.

SolStream installs and enables `seatd`, ensures the streaming user is in `video`, and depends on `seatd.service` from `gamescope-sunshine.service`.

## Source builds and why

Two things have to be source-built on Ubuntu 24.04 because the packaged versions are too old:

1. **wayland 1.23.x** — gamescope's bundled wlroots fork requires `wayland-server >= 1.23`; noble ships 1.22. Source-built to `/usr/local`. `ldconfig` resolves `/usr/local/lib/...` ahead of `/usr/lib/...` by default, so gamescope picks it up automatically; nothing else on the system uses 1.23+ APIs so no regression.

2. **gamescope itself** — packaged versions lag and don't always include the Steam Deck patches we need. Pinned to a known-good tag (currently `3.16.23`).

When building gamescope you only get the **x86_64** Vulkan WSI layer by default. Steam's main process is 32-bit, so it needs a matching **i686** layer to avoid a "Gamescope WSI Layer Error" popup at startup. SolStream cross-compiles the i686 variant of just the WSI subdirectory using a meson cross-file and installs it to `/usr/local/lib/i386-linux-gnu/`.

## Lifecycle: one systemd user unit owns everything

`gamescope-sunshine.service` is a *user* systemd unit (via `loginctl enable-linger`) that runs:

```
gamescope --backend drm --prefer-output DP-1 ... -- /usr/local/bin/solstream-session.sh
```

`solstream-session.sh` is the inner-cmd wrapper that:

1. Sets `WAYLAND_DISPLAY=gamescope-0` and `VK_LOADER_LAYERS_DISABLE=...` (disables NV_optimus and friends that interfere with the WSI layer).
2. Drops a `zenity` stub on PATH so steam-installer's first-run prompt auto-accepts.
3. Loads a PipeWire null sink (`Sunshine-Sink`) idempotently.
4. Spawns Steam Big Picture in the background.
5. `exec`s Sunshine in the foreground.

When Sunshine exits (or crashes), the wrapper's exit handler runs, calls `steam -shutdown` (gracefully), waits, then SIGKILLs anything still alive. systemd's `Restart=on-failure` brings the whole unit back. Cold-boot recovery is verified by reboot.

The user lingers, so the unit survives logout. The unit depends on `pipewire.service` so audio is ready before Sunshine probes for a sink.

## Roles map

Each Ansible role does one of the things above:

| Role | Solves | Idempotent state check |
|---|---|---|
| `nvidia-driver` | Driver branch / SB / signed modules | `nvidia-smi` returns + correct module package |
| `kernel-modeset` | GRUB cmdline, synthetic EDID, initramfs | `/sys/class/drm/card0-DP-1/status == connected` |
| `gamescope-build` | wayland 1.23 + gamescope + x86_64 & i686 WSI | `gamescope --version` returns expected tag, both `.so` files present |
| `steam` | i386 multiarch + Steam runtime bootstrap | `~/.steam/debian-installation/bootstrap.tar.xz` exists |
| `sunshine` | LizardByte release `.deb` + config + apps.json | `sunshine --version` matches pinned, web UI returns 307 |
| `pipewire-session` | User PipeWire + `pulseaudio-utils` for `pactl` | `pactl list sinks` includes `Sunshine-Sink` after wrapper runs |
| `session-wrapper` | `solstream-session.sh` + systemd unit | Unit active, Steam BPM window visible via xwininfo |
| `wireguard` | wg-easy + DDNS notes | wg-easy container running, peer added if requested |
| `discoverability` | MOTD, `solstream urls`, optional dashboard | URLs print on login |
| `doctor` | Health checks, called by `solstream doctor` | All checks pass green |

Roles have explicit `meta/main.yml` dependencies — e.g., `gamescope-build` depends on `nvidia-driver` having run and a reboot having happened.

## What the web installer does

The web installer (`webui/`) is a small Python app that:

1. Detects the host's hardware (GPU, kernel, distro, Secure Boot state)
2. Asks the user to pick targets (resolution, FPS, codec, encoder preset, optional WG setup)
3. Generates an Ansible inventory + variables file matching the choices
4. Invokes `ansible-playbook` and streams its output to a WebSocket in the browser
5. On success, shows a final URL list (Sunshine UI, wg-easy admin, status page)

It exists as a layer over Ansible, not a replacement. Power users skip it; non-Ansible users get a familiar wizard UX.
