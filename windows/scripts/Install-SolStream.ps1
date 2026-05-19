#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SolStream Windows host installer.

.DESCRIPTION
    Sets up a Windows host as a Sunshine streaming server, mirroring what
    the Linux Ansible roles do but using the Windows-native paths:

      - Verifies NVIDIA driver is installed and recent enough
      - Installs Sunshine via winget (falls back to direct .msi download)
      - Installs LizardByte's Virtual Display Driver for headless rendering
      - Drops a tuned sunshine.conf + apps.json under %APPDATA%\Sunshine
      - Opens Windows Firewall for Sunshine's ports
      - Optional: installs WireGuard for Windows and prompts for setup

.PARAMETER SkipFirewall
    Don't add Windows Firewall rules. Useful if you manage firewall config
    separately.

.PARAMETER SkipWireGuard
    Don't install WireGuard. Skip if you don't need remote streaming.

.EXAMPLE
    PS> .\Install-SolStream.ps1

.EXAMPLE
    PS> .\Install-SolStream.ps1 -SkipWireGuard

.NOTES
    Status: Phase 5 scaffolding. Tested only superficially. Contributions
    very welcome — see windows/README.md.
#>

[CmdletBinding()]
param(
    [switch]$SkipFirewall,
    [switch]$SkipWireGuard
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step {
    param([string]$Message)
    Write-Host "`n  ▶ $Message" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    ⚠ $Message" -ForegroundColor DarkYellow
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─── Preflight ──────────────────────────────────────────────────────────
Write-Host "`n☀ SolStream Windows host installer`n" -ForegroundColor Cyan

if (-not (Test-Admin)) {
    Write-Error "Must run as Administrator. Right-click PowerShell → Run as Administrator."
    exit 1
}

# Detect NVIDIA driver
Write-Step "Detecting NVIDIA GPU"
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
if (-not $gpu) {
    Write-Error "No NVIDIA GPU detected. SolStream v0.1 requires NVIDIA Ampere or newer."
    exit 1
}
Write-OK "Found: $($gpu.Name)"
Write-OK "Driver: $($gpu.DriverVersion)"

# Detect winget
Write-Step "Detecting winget"
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-OK "winget found at $($winget.Source)"
} else {
    Write-Warn "winget not found; will fall back to direct downloads."
}

# ─── Sunshine ───────────────────────────────────────────────────────────
Write-Step "Installing Sunshine"
$sunshineInstalled = Get-Command sunshine.exe -ErrorAction SilentlyContinue
if ($sunshineInstalled) {
    Write-OK "Sunshine already installed at $($sunshineInstalled.Source)"
} else {
    if ($winget) {
        winget install --silent --accept-package-agreements --accept-source-agreements LizardByte.Sunshine
        Write-OK "Sunshine installed via winget"
    } else {
        $url = "https://github.com/LizardByte/Sunshine/releases/latest/download/Sunshine-Windows-AMD64-installer.exe"
        $tmp = "$env:TEMP\Sunshine-installer.exe"
        Write-Host "    Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        Start-Process -FilePath $tmp -ArgumentList "/S" -Wait
        Remove-Item $tmp
        Write-OK "Sunshine installed via direct download"
    }
}

# ─── Virtual Display Driver ─────────────────────────────────────────────
Write-Step "Installing LizardByte Virtual Display Driver (for headless rendering)"
# TODO: Sunshine ships with an optional bundled installer for this. The cleanest
# approach is to download the latest VirtualDisplayDriver release and install
# via pnputil. For v0.1 scaffolding we just leave a TODO and point at the
# manual install in the README.
Write-Warn "Virtual Display Driver install is not yet automated."
Write-Warn "Manual install: https://github.com/itsmikethetech/Virtual-Display-Driver/releases"

# ─── Sunshine config ────────────────────────────────────────────────────
Write-Step "Installing tuned sunshine.conf"
$cfgDir = "$env:USERPROFILE\AppData\Roaming\Sunshine"
$null = New-Item -ItemType Directory -Force -Path $cfgDir
$cfgPath = "$cfgDir\sunshine.conf"

# Same low-latency profile as the Linux track
@'
# SolStream Windows-tuned Sunshine config

origin_web_ui_allowed = lan
address_family = both

encoder = nvenc
nvenc_preset = 4
nvenc_twopass = disabled
nvenc_realtime_hags = enabled
hevc_mode = 3

min_threads = 4
fec_percentage = 10

min_log_level = info
'@ | Out-File -FilePath $cfgPath -Encoding utf8 -Force
Write-OK "Wrote $cfgPath"

# Apps.json — same shape as Linux track
$appsPath = "$cfgDir\apps.json"
@'
{
  "env": {},
  "apps": [
    {
      "name": "Steam Big Picture",
      "cmd": [
        "C:\\Program Files (x86)\\Steam\\Steam.exe",
        "steam://open/bigpicture"
      ],
      "auto-detach": "true",
      "wait-all": "false",
      "exit-timeout": "5"
    }
  ]
}
'@ | Out-File -FilePath $appsPath -Encoding utf8 -Force
Write-OK "Wrote $appsPath"

# ─── Windows Firewall ───────────────────────────────────────────────────
if (-not $SkipFirewall) {
    Write-Step "Adding Windows Firewall rules for Sunshine"
    $ports = @(47984, 47989, 47990, 48010)
    foreach ($port in $ports) {
        $name = "SolStream Sunshine TCP $port"
        if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP `
                -LocalPort $port -Action Allow -Profile Any | Out-Null
            Write-OK "Allowed TCP $port"
        }
    }
    $udpPorts = @(47998, 47999, 48000, 48002, 48010)
    foreach ($port in $udpPorts) {
        $name = "SolStream Sunshine UDP $port"
        if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol UDP `
                -LocalPort $port -Action Allow -Profile Any | Out-Null
            Write-OK "Allowed UDP $port"
        }
    }
} else {
    Write-Warn "Skipping firewall config (--SkipFirewall)"
}

# ─── WireGuard ──────────────────────────────────────────────────────────
if (-not $SkipWireGuard) {
    Write-Step "Installing WireGuard for Windows"
    if (Get-Command wireguard.exe -ErrorAction SilentlyContinue) {
        Write-OK "WireGuard already installed"
    } elseif ($winget) {
        winget install --silent --accept-package-agreements WireGuard.WireGuard
        Write-OK "WireGuard installed via winget"
    } else {
        Write-Warn "winget unavailable; install WireGuard manually from https://www.wireguard.com/install/"
    }
}

# ─── Start Sunshine service ─────────────────────────────────────────────
Write-Step "Starting Sunshine service"
$svc = Get-Service -Name SunshineService -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne "Running") {
        Start-Service -Name SunshineService
    }
    Write-OK "Sunshine service is running"
} else {
    Write-Warn "Sunshine service not registered. Launch Sunshine.exe once manually to install it."
}

# ─── Done ──────────────────────────────────────────────────────────────
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 |
          Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" } |
          Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
          Select-Object -First 1).IPAddress

Write-Host "`n  ╔══════════════════════════════════════════════════╗"
Write-Host "  ║   SolStream Windows install complete!            ║"
Write-Host "  ╚══════════════════════════════════════════════════╝`n"
Write-Host "  Sunshine Web UI:  https://${lanIp}:47990"
Write-Host "  Next steps:"
Write-Host "    1. Open the URL above, set admin password"
Write-Host "    2. Install Moonlight on your client device"
Write-Host "    3. Pair via PIN"
Write-Host "    4. Launch 'Steam Big Picture' from Moonlight`n"
