# Hardware support

Status definitions:

- **🟢 Tested** — actively verified on real hardware running SolStream
- **🔵 CI-checked** — playbook syntax + apt resolution validated in CI, not on real hardware
- **🟡 Should work** — code path exists, untested on this specific config (contributions welcome)
- **🟠 Partial** — works for some features but not others
- **🔴 Not supported** — known to not work, no current plan

What CI does *not* check:
- Driver actually loading
- Streaming end-to-end
- Anything requiring real GPU (it runs on GitHub Actions; no GPU)

For the things CI can't check, the reference deployment ([private repo](https://github.com/mxmjxn/HeadlessEntertainment)) on RTX 3070 / Ubuntu 24.04 / Secure Boot enabled is the live source of truth.

## Host OS

| OS | Status | Notes |
|---|---|---|
| Ubuntu 24.04 LTS (Noble) | 🟢 Tested + 🔵 CI-checked | Reference platform |
| Ubuntu 24.10 / 25.04 | 🟡 Should work | Newer kernel; check `linux-modules-nvidia-*` availability |
| Debian 13 (Trixie) | 🟡 Should work | Sunshine ships a `-debian-trixie-amd64.deb` officially |
| Pop_OS 22.04 / 24.04 | 🟡 Should work | Pop ships its own NVIDIA stack; SolStream's driver role needs a small branch |
| Ubuntu 22.04 LTS (Jammy) | 🟠 Partial | Sunshine releases support it, but gamescope 3.16+ may need newer Mesa than Jammy ships |
| Bazzite | 🔴 Not needed | Bazzite is already a SolStream-equivalent ecosystem; use it directly |
| Arch / Manjaro | 🔴 Not supported v1 | Different package management; can be added but isn't a priority |
| RHEL / Rocky / Alma | 🔴 Not supported v1 | NVIDIA driver path differs significantly |

## GPU

| GPU family | Encoder | Status | Notes |
|---|---|---|---|
| NVIDIA RTX 30-series (Ampere) | NVENC 7th gen — H.264, HEVC 8/10-bit | 🟢 Tested | Reference platform; no AV1 encode |
| NVIDIA RTX 40-series (Ada) | NVENC 8th gen — H.264, HEVC, **AV1** | 🟡 Should work | Same driver branch as Ampere; AV1 needs Moonlight 5.0+ on client |
| NVIDIA RTX 50-series (Blackwell) | NVENC 9th gen — adds AV1 improvements | 🟡 Should work | May need newer driver branch than what we pin |
| NVIDIA GTX 16-series (Turing budget) | NVENC 6th gen — no AV1 | 🟡 Should work | Lower encode quality at same bitrate |
| NVIDIA RTX 20-series (Turing) | NVENC 6th gen | 🟡 Should work | Same as GTX 16 |
| NVIDIA GTX 10-series (Pascal) | NVENC 5th gen | 🟠 Partial | Only open kernel modules from Ampere+; falls back to proprietary modules path |
| AMD Radeon (RDNA 2/3) | VAAPI — H.264, HEVC, AV1 (RDNA3) | 🔴 Not v1 | Separate driver role; works with vanilla Sunshine, just no SolStream automation yet |
| Intel Arc | QSV — H.264, HEVC, AV1 | 🔴 Not v1 | Driver maturity issues + no encoder in current Sunshine on Arc |
| Intel iGPU (UHD 7xx etc.) | QSV — H.264, HEVC | 🔴 Not v1 | Insufficient encode throughput for 1440p120 |

## CPU

No hard requirements. Recommended:

- **4+ physical cores** so encoder + game + OS don't compete
- **AVX2** is helpful for some game workloads
- **AMD Zen 2+** or **Intel 10th gen+** is the sweet spot

Tested reference: **AMD Ryzen 7 5800X (8c/16t)**. The encoder uses NVENC on the GPU, not CPU, so the CPU primarily runs the game. Modest CPUs (Ryzen 3, i3) work fine for lighter games.

## RAM

- **16 GB minimum**
- **32 GB recommended** so OS file cache, Steam, and the game all fit
- Steam libraries with many active games benefit from more

## Storage

- **System disk:** 50 GB free for OS + Steam runtime + cached dependencies
- **Game library:** size to taste. NVMe SSD strongly recommended (game load times directly affect stream UX)
- Steam library on a path under `/data/...` (or anywhere mountable) — SolStream defaults to `/data/downloads/steamlibrary` but you can change in the installer

## Network — host side

- **Wired Gigabit Ethernet** strongly preferred
- LAN MTU: 1500 default is fine
- Wi-Fi: works but introduces 5–15 ms jitter; the host should never be on Wi-Fi if avoidable

## Network — client side

Bitrate guidelines vs. connection type:

| Connection | Recommended bitrate | Resolution |
|---|---|---|
| Wired Gigabit LAN | 50–80 Mbps | 1440p120 / 4K60 |
| Wi-Fi 6 (5 GHz, close) | 30–50 Mbps | 1440p60 / 1080p120 |
| Wi-Fi 5 (5 GHz) | 20–30 Mbps | 1080p60 |
| Internet via WG (good upload) | 15–25 Mbps | 1080p60 |
| Mobile data (LTE/5G) | 5–10 Mbps | 720p60 |

## Moonlight clients

We don't build the clients — these are just for reference. All work with SolStream:

| Client device | Maximum quality | Notes |
|---|---|---|
| NVIDIA Shield TV 2019 Pro | 4K HEVC 10-bit, 60 fps | Best mainstream client by far |
| Apple TV 4K (gen 2+) | 4K HEVC 10-bit, 60 fps | HDMI 2.0, no 120 Hz |
| Moonlight PC (Win/Mac/Linux) | 4K120, AV1, HDR | Reference / debug client |
| Steam Deck | 1280×800 native, 60 fps | Moonlight Flatpak — works well |
| Android phone/tablet | 4K60 HEVC | App-store install |
| iPhone/iPad | 4K60 HEVC | App-store install; gamepad emulation on-screen is poor — pair Bluetooth controller |
| Apple Vision Pro | Via 3rd-party port | Experimental |
| Stock Chromecast | ❌ | Cannot run Moonlight; needs Google TV variant minimum, and even then 1080p60 ceiling |

## Display attached to host?

Not required. SolStream is specifically designed for **fully headless** operation — no monitor, no keyboard, no mouse plugged into the host. If you have an attached display it'll briefly show the SolStream session at boot, then go to sleep. Doesn't affect anything.

## IPMI / BMC / remote console

Not required, but **strongly recommended** for any kind of production server. If you ever need to:

- Recover from a bad GRUB config
- Disable Secure Boot
- Enroll a MOK
- Re-run the BIOS/UEFI menu

…you'll need physical access or IPMI/KVM. SolStream tries to keep all changes recoverable from a working SSH session, but kernel cmdline edits are inherently risky.

If you have an SBC-class machine (NUC, mini-PC) without IPMI, consider a [PiKVM](https://pikvm.org/) ($150ish) or similar IP-KVM solution.
