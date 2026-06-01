#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SolStream Windows host installer (command-line front-end).

.DESCRIPTION
    Thin CLI wrapper over SolStreamInstall.psm1. For a graphical wizard,
    use Install-SolStream-GUI.ps1 instead - both share the same module.

.PARAMETER NvencPreset
    NVENC preset 1-7 (P1 slowest/best quality .. P7 fastest). Default 4.

.PARAMETER SteamPath
    Full path to Steam.exe. Default C:\Program Files (x86)\Steam\Steam.exe.

.PARAMETER SkipFirewall
    Don't add Windows Firewall rules.

.PARAMETER EnableWireGuard
    Install WireGuard for Windows for remote streaming.

.EXAMPLE
    PS> .\Install-SolStream.ps1

.EXAMPLE
    PS> .\Install-SolStream.ps1 -NvencPreset 1 -EnableWireGuard

.NOTES
    Status: Phase 5 scaffolding. Untested on real Windows hardware.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 7)][int]$NvencPreset = 4,
    [string]$SteamPath = 'C:\Program Files (x86)\Steam\Steam.exe',
    [switch]$SkipFirewall,
    [switch]$EnableWireGuard,
    [switch]$SkipSteam,
    [switch]$InstallVirtualDisplay
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import the shared install module
$modulePath = Join-Path $PSScriptRoot 'SolStreamInstall.psm1'
Import-Module $modulePath -Force

# Coloured console logger
$consoleLogger = {
    param($Message, $Level = 'info')
    $color = switch ($Level) {
        'ok'    { 'Green' }
        'warn'  { 'DarkYellow' }
        'error' { 'Red' }
        default { 'Gray' }
    }
    $prefix = switch ($Level) {
        'ok'    { '  [ok]   ' }
        'warn'  { '  [warn] ' }
        'error' { '  [FAIL] ' }
        default { '  ->     ' }
    }
    Write-Host "$prefix$Message" -ForegroundColor $color
}

Write-Host "`n  SolStream Windows host installer (CLI)`n" -ForegroundColor Cyan

# Verify Administrator
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Must run as Administrator. Right-click PowerShell -> Run as Administrator.'
    exit 1
}

try {
    Invoke-SolStreamInstall `
        -NvencPreset $NvencPreset `
        -SteamPath $SteamPath `
        -EnableFirewall (-not $SkipFirewall) `
        -EnableWireGuard ([bool]$EnableWireGuard) `
        -InstallSteam (-not $SkipSteam) `
        -InstallVirtualDisplay ([bool]$InstallVirtualDisplay) `
        -Log $consoleLogger

    Write-Host "`n  Done. Next steps:" -ForegroundColor Cyan
    Write-Host '    1. Open the Sunshine Web UI (printed above), set admin password'
    Write-Host '    2. Install Moonlight on your client device'
    Write-Host '    3. Pair via PIN'
    Write-Host "    4. Launch 'Steam Big Picture' from Moonlight`n"
}
catch {
    Write-Host "`n  Install failed: $_`n" -ForegroundColor Red
    exit 1
}
