# SolStream on Windows

The Windows track is **scaffolding-level** as of v0.1. A working PowerShell installer + `Test-SolStream.ps1` doctor are in place but haven't been exercised on real Windows hardware yet. **Contributions very welcome** — see "What needs work" at the bottom.

## TL;DR — installing today

From an elevated PowerShell prompt on a Windows 11 host with an NVIDIA GPU:

```powershell
# 1. Clone the repo
git clone https://github.com/mxmjxn/SolStream.git C:\SolStream
cd C:\SolStream\windows\scripts

# 2a. GRAPHICAL installer (recommended — pick options in a window)
Set-ExecutionPolicy -Scope Process Bypass
.\Install-SolStream-GUI.ps1

# 2b. OR command-line installer
.\Install-SolStream.ps1            # accepts -NvencPreset, -SteamPath,
                                   # -SkipFirewall, -EnableWireGuard

# 3. After install, run the doctor
.\Test-SolStream.ps1
```

Either installer installs Sunshine, drops a tuned `sunshine.conf` + `apps.json` at `%APPDATA%\Sunshine\`, opens Windows Firewall for Sunshine's ports, and (optionally) installs WireGuard for Windows.

### Graphical installer

`Install-SolStream-GUI.ps1` opens a WPF window that:

- Shows detected hardware (GPU, driver, Sunshine status) and disables Install on non-NVIDIA hosts
- Lets you pick NVENC preset, Steam executable path (with a Browse button), and toggle firewall rules + WireGuard
- Runs the install in a background runspace so the window stays responsive, streaming progress into a log pane
- Self-elevates (relaunches as Administrator) if you didn't start it elevated

Both front-ends share their install logic via `SolStreamInstall.psm1` — there is no duplicated install code between the CLI and GUI.

### Architecture

```
SolStreamInstall.psm1          <- all install logic (one source of truth)
├── Install-SolStream.ps1      <- CLI front-end
└── Install-SolStream-GUI.ps1  <- WPF GUI front-end
Test-SolStream.ps1             <- health check ("doctor")
```

## Why Windows is a separate, smaller track

Most of what makes SolStream's Linux installer complex doesn't apply to Windows:

| Linux problem | Windows equivalent |
|---|---|
| gamescope compositor | Native DWM compositor; not needed |
| Synthetic EDID + DRM modeset | Sunshine has a [Virtual Display Driver](https://github.com/itsmikethetech/Virtual-Display-Driver) you click-install |
| NVIDIA driver branch / DKMS / Secure Boot | One installer from nvidia.com, signed by NVIDIA, just works |
| seatd / libseat for DRM-master | N/A — Windows GPU access is unprivileged |
| PipeWire null-sink | Sunshine includes Windows audio capture natively |
| Steam first-run zenity bootstrap | Steam's Windows installer is a normal .msi |
| systemd user units | Windows Service / Task Scheduler |
| Cross-compiled i686 WSI Vulkan layer | N/A — DXGI, not Vulkan, on Windows |
| ISP filter blocking DDNS | Same problem — same fix (see `../docs/router-setup.md`) |

About 80% of the Linux installer's value is "knowing how to get past these gotchas." Windows skips most of them.

## What's actually here

```
windows/
├── README.md                       This file
├── PSScriptAnalyzerSettings.psd1   Lint config (excludes Write-Host etc.)
├── scripts/
│   ├── SolStreamInstall.psm1       Shared install logic (one source of truth)
│   ├── Install-SolStream.ps1       CLI front-end
│   ├── Install-SolStream-GUI.ps1   WPF graphical front-end
│   └── Test-SolStream.ps1          Health-check ("doctor")
├── winget-manifest/
│   └── README.md                   Plans for shipping via winget (not yet generated)
└── docs/                           (Empty; will hold Windows-specific docs)
```

## What needs work

**Help wanted on:**

1. **Virtual Display Driver automation.** The installer currently leaves this as a manual step. Should download the latest VDD release, run `pnputil /add-driver` with the inf file, then enable it.
2. **Steam Big Picture path detection.** The hardcoded `C:\Program Files (x86)\Steam\Steam.exe` won't work for users who installed Steam elsewhere.
3. **Sunshine virtual display profile.** When SolStream's Sunshine config is paired with VDD, the right `output_name` setting needs to point at the virtual display.
4. **Windows Server / Datacenter SKUs.** Untested. NVENC on those SKUs has different licensing implications.
5. **Real testing on hardware.** Everything in this directory is theoretically correct based on the Linux deployment and Sunshine documentation, but no one has actually run it on Windows yet.
6. **winget manifest generation + PR.** See `winget-manifest/README.md`.
7. **A web installer for Windows.** The Python webui is OS-agnostic — could ship a Windows variant of `install.sh` (PowerShell bootstrap) that downloads the venv approach to a Windows host.

If you have a Windows 11 machine with an NVIDIA GPU and an hour to spare, opening a PR with whatever you found broken would be the single most valuable contribution to SolStream right now.
