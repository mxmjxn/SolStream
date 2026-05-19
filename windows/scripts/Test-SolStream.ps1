#Requires -Version 5.1
<#
.SYNOPSIS
    Windows equivalent of `solstream doctor` — health checks for a Windows
    SolStream install.

.DESCRIPTION
    Runs a set of checks and reports green/red status per item. Mirrors the
    Linux `doctor` Ansible role's checklist where possible.

.EXAMPLE
    PS> .\Test-SolStream.ps1

.NOTES
    Phase 5 scaffolding; checks will grow as the Windows install path
    matures.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

$results = @()

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    $script:results += [PSCustomObject]@{
        Name   = $Name
        OK     = $Ok
        Detail = $Detail
    }
}

# ─── NVIDIA driver ──────────────────────────────────────────────────────
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
Add-Result "NVIDIA GPU" ($null -ne $gpu) ($gpu.Name -as [string])
Add-Result "NVIDIA driver version" ($null -ne $gpu) ($gpu.DriverVersion -as [string])

# ─── Sunshine ───────────────────────────────────────────────────────────
$sunshine = Get-Command sunshine.exe -ErrorAction SilentlyContinue
Add-Result "Sunshine installed" ($null -ne $sunshine) ($sunshine.Source -as [string])

$svc = Get-Service -Name SunshineService -ErrorAction SilentlyContinue
Add-Result "SunshineService registered" ($null -ne $svc) ($svc.Status -as [string])
if ($svc) {
    Add-Result "SunshineService running" ($svc.Status -eq "Running") $svc.Status
}

# ─── Config files ───────────────────────────────────────────────────────
$cfg = "$env:USERPROFILE\AppData\Roaming\Sunshine\sunshine.conf"
Add-Result "sunshine.conf present" (Test-Path $cfg) $cfg

$apps = "$env:USERPROFILE\AppData\Roaming\Sunshine\apps.json"
Add-Result "apps.json present" (Test-Path $apps) $apps

# ─── Ports listening ────────────────────────────────────────────────────
$ports = @(47984, 47989, 47990, 48010)
foreach ($port in $ports) {
    $listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    Add-Result "TCP port $port listening" ($null -ne $listening) ""
}

# ─── Firewall rules ─────────────────────────────────────────────────────
$rule = Get-NetFirewallRule -DisplayName "SolStream Sunshine TCP 47984" -ErrorAction SilentlyContinue
Add-Result "Firewall rules present" ($null -ne $rule) ""

# ─── Render summary ─────────────────────────────────────────────────────
Write-Host "`n  ── SolStream doctor (Windows) ──`n" -ForegroundColor Cyan
foreach ($r in $results) {
    $mark = if ($r.OK) { "✓" } else { "✗" }
    $color = if ($r.OK) { "Green" } else { "Red" }
    Write-Host ("    {0,-2}  {1,-30}  {2}" -f $mark, $r.Name, $r.Detail) -ForegroundColor $color
}

$failed = ($results | Where-Object { -not $_.OK }).Count
Write-Host "`n  $failed check(s) failed.`n" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

exit $failed
