# SolStream on Windows

> **Phase 5 of the project plan — not yet implemented.**

## TL;DR for now

If you want to run SolStream-equivalent on a Windows host **today**:

1. Install Sunshine for Windows from the [official release](https://github.com/LizardByte/Sunshine/releases) → `Sunshine-Windows-AMD64-installer.exe`
2. Copy a tuned `sunshine.conf` from `../files/sunshine-templates/sunshine-windows.conf` over the default
3. Add Steam Big Picture as a managed app in Sunshine's Web UI
4. (Optional) Set up WireGuard on Windows for remote streaming — follow [WireGuard's Windows guide](https://www.wireguard.com/install/), then forward `51820/UDP` per `../docs/router-setup.md`

That covers ~95% of what SolStream automates on Linux. Windows handles the rest (driver signing, virtual displays, audio routing) natively because the OS includes it.

## Why Windows is a separate, smaller track

Most of what makes SolStream's Linux installer complex doesn't apply to Windows:

| Linux problem | Windows equivalent |
|---|---|
| gamescope compositor | Native DWM compositor; not needed |
| Synthetic EDID + DRM modeset | Sunshine has a [Windows virtual display driver](https://github.com/LizardByte/Virtual-Display-Driver) you click-install |
| NVIDIA driver branch / DKMS / Secure Boot | One installer from nvidia.com, signed by NVIDIA, just works |
| seatd / libseat for DRM-master | N/A — Windows GPU access is unprivileged |
| PipeWire null-sink | Sunshine includes a Windows audio capture path natively |
| Steam first-run zenity bootstrap | Steam's Windows installer is a normal .msi |
| systemd user units | Windows Service / Task Scheduler |
| Cross-compiled i686 WSI Vulkan layer | N/A — DXGI, not Vulkan, on Windows |
| ISP filter blocking DDNS | Same problem — same fix (disable filter, see `../docs/router-setup.md`) |

About 80% of the Linux installer's value is "knowing how to get past these gotchas." Windows skips most of them.

## What this directory will eventually contain

- `Install-SolStream.ps1` — PowerShell installer that:
  - Verifies NVIDIA driver version
  - Installs Sunshine via winget (when it's in winget) or downloads the .msi
  - Installs the Virtual-Display-Driver
  - Lays down our tuned `sunshine.conf` + `apps.json`
  - Opens Windows Firewall for Sunshine's ports
  - Sets Steam Big Picture as the default app
- `winget-manifest/` — PR-ready winget manifest for `solstream` so users can `winget install solstream`
- `Test-SolStream.ps1` — equivalent of `solstream doctor` for Windows
- Optional: a Windows version of the web installer, since the Python code is OS-agnostic

## Status

Not started. Contributions very welcome — much of this is straightforward PowerShell, and the Sunshine project has good Windows install docs as a starting point.
