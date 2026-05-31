<#
.SYNOPSIS
    Shared install logic for SolStream on Windows.

.DESCRIPTION
    This module contains the actual install steps. Two front-ends consume it:
      - Install-SolStream.ps1       (command-line)
      - Install-SolStream-GUI.ps1   (WPF graphical wizard)

    Every function accepts an optional -Log scriptblock so the caller controls
    where progress goes (console for the CLI, a textbox for the GUI). The
    default logger writes to the host.

    Status: Phase 5 scaffolding. Structurally correct + linted in CI, but
    untested on real Windows hardware. Contributions welcome.
#>

Set-StrictMode -Version Latest

# Default logger - callers override with their own scriptblock.
$script:DefaultLogger = { param($Message, $Level = 'info') Write-Host $Message }

function Write-SolStreamLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('info', 'ok', 'warn', 'error')][string]$Level = 'info',
        [scriptblock]$Log
    )
    $logger = if ($Log) { $Log } else { $script:DefaultLogger }
    & $logger $Message $Level
}

function Get-SolStreamHardware {
    <#
    .SYNOPSIS
        Probe the host for GPU, driver, Sunshine, and network info.
    .OUTPUTS
        Hashtable with keys: GpuVendor, GpuModel, DriverVersion, HasNvidia,
        SunshineInstalled, SunshineVersion, WingetAvailable, LanIp.
    #>
    [CmdletBinding()]
    param()

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'NVIDIA' } |
        Select-Object -First 1

    $sunshine = Get-Command sunshine.exe -ErrorAction SilentlyContinue
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.PrefixOrigin -eq 'Dhcp' -or $_.PrefixOrigin -eq 'Manual') -and
            $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1'
        } | Select-Object -First 1).IPAddress

    return @{
        GpuVendor         = if ($gpu) { 'NVIDIA' } else { 'unknown' }
        GpuModel          = if ($gpu) { $gpu.Name } else { 'No NVIDIA GPU detected' }
        DriverVersion     = if ($gpu) { $gpu.DriverVersion } else { '' }
        HasNvidia         = [bool]$gpu
        SunshineInstalled = [bool]$sunshine
        SunshineVersion   = if ($sunshine) { (& sunshine.exe --version 2>&1 | Select-Object -First 1) } else { '' }
        WingetAvailable   = [bool]$winget
        LanIp             = if ($lanIp) { $lanIp } else { '127.0.0.1' }
    }
}

function Invoke-SolStreamWinget {
    <#
    .SYNOPSIS
        Run a winget install robustly from automation / a runspace.
    .DESCRIPTION
        Calling winget directly inside a background runspace can hang
        indefinitely because the runspace has no console/stdin for winget's
        interactive elements. We instead launch winget via Start-Process
        with output redirected to temp files (clean process context),
        --disable-interactivity to forbid prompts, and a timeout so a stuck
        winget surfaces an error instead of hanging the installer forever.
    .OUTPUTS
        $true on success (exit 0), $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [int]$TimeoutSeconds = 600,
        [scriptblock]$Log
    )

    $wingetArgs = @(
        'install', '--id', $PackageId, '--exact',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )
    $outFile = Join-Path $env:TEMP "solstream-winget-out-$PackageId.txt"
    $errFile = Join-Path $env:TEMP "solstream-winget-err-$PackageId.txt"

    Write-SolStreamLog "Running: winget $($wingetArgs -join ' ')" 'info' -Log $Log
    Write-SolStreamLog 'This can take several minutes with no per-file progress shown here.' 'info' -Log $Log

    $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch { }
        Write-SolStreamLog "winget timed out after ${TimeoutSeconds}s installing $PackageId." 'error' -Log $Log
        return $false
    }

    # Surface the captured output into the log
    foreach ($f in @($outFile, $errFile)) {
        if (Test-Path $f) {
            Get-Content $f | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
                Write-SolStreamLog "  winget: $_" 'info' -Log $Log
            }
            Remove-Item $f -ErrorAction SilentlyContinue
        }
    }

    if ($proc.ExitCode -eq 0) {
        Write-SolStreamLog "$PackageId installed via winget." 'ok' -Log $Log
        return $true
    }
    Write-SolStreamLog "winget exited $($proc.ExitCode) installing $PackageId." 'error' -Log $Log
    return $false
}

function Install-SolStreamSunshine {
    [CmdletBinding()]
    param([scriptblock]$Log)

    if (Get-Command sunshine.exe -ErrorAction SilentlyContinue) {
        Write-SolStreamLog 'Sunshine already installed.' 'ok' -Log $Log
        return
    }

    $wingetOk = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-SolStreamLog 'Installing Sunshine via winget...' 'info' -Log $Log
        $wingetOk = Invoke-SolStreamWinget -PackageId 'LizardByte.Sunshine' -Log $Log
    }

    if (-not $wingetOk) {
        Write-SolStreamLog 'Falling back to direct .exe download from GitHub...' 'warn' -Log $Log
        $url = 'https://github.com/LizardByte/Sunshine/releases/latest/download/Sunshine-Windows-AMD64-installer.exe'
        $tmp = Join-Path $env:TEMP 'Sunshine-installer.exe'
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        Start-Process -FilePath $tmp -ArgumentList '/S' -Wait
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-SolStreamLog 'Sunshine installed via direct download.' 'ok' -Log $Log
    }
}

function Set-SolStreamSunshineConfig {
    <#
    .SYNOPSIS
        Write the tuned sunshine.conf + apps.json.
    #>
    [CmdletBinding()]
    param(
        [int]$NvencPreset = 4,
        [int]$HevcMode = 3,
        [int]$FecPercentage = 10,
        [int]$MinThreads = 4,
        [string]$SteamPath = 'C:\Program Files (x86)\Steam\Steam.exe',
        [scriptblock]$Log
    )

    $cfgDir = Join-Path $env:USERPROFILE 'AppData\Roaming\Sunshine'
    $null = New-Item -ItemType Directory -Force -Path $cfgDir

    $conf = @"
# SolStream Windows-tuned Sunshine config

origin_web_ui_allowed = lan
address_family = both

encoder = nvenc
nvenc_preset = $NvencPreset
nvenc_twopass = disabled
nvenc_realtime_hags = enabled
hevc_mode = $HevcMode

min_threads = $MinThreads
fec_percentage = $FecPercentage

min_log_level = info
"@
    $confPath = Join-Path $cfgDir 'sunshine.conf'
    # Use ASCII (no BOM). PS 5.1's `-Encoding utf8` emits a BOM, which some
    # JSON/config parsers reject. Content here is all ASCII anyway.
    $conf | Out-File -FilePath $confPath -Encoding ascii -Force
    Write-SolStreamLog "Wrote $confPath" 'ok' -Log $Log

    # Build apps.json with ConvertTo-Json rather than hand-written text.
    # This auto-escapes the Steam path's backslashes and removes all the
    # string-escaping landmines (notably $_ in the quit-game command, which
    # must stay LITERAL - a single-quoted string guarantees no interpolation).
    $quitCmd = 'Get-Process | Where-Object { $_.Path -like ''*steamapps*'' } | Stop-Process -Force'

    $appsObj = [ordered]@{
        env  = [ordered]@{}
        apps = @(
            [ordered]@{
                name           = 'Steam Big Picture'
                cmd            = @($SteamPath, 'steam://open/bigpicture')
                'auto-detach'  = 'true'
                'wait-all'     = 'false'
                'exit-timeout' = '5'
            },
            [ordered]@{
                name           = 'Quit current game'
                cmd            = @('powershell', '-NoProfile', '-Command', $quitCmd)
                'auto-detach'  = 'false'
                'wait-all'     = 'true'
                'exit-timeout' = '10'
            }
        )
    }
    $appsPath = Join-Path $cfgDir 'apps.json'
    $appsObj | ConvertTo-Json -Depth 6 | Out-File -FilePath $appsPath -Encoding ascii -Force
    Write-SolStreamLog "Wrote $appsPath" 'ok' -Log $Log
}

function Add-SolStreamFirewallRules {
    [CmdletBinding()]
    param([scriptblock]$Log)

    $tcpPorts = @(47984, 47989, 47990, 48010)
    $udpPorts = @(47998, 47999, 48000, 48002, 48010)

    foreach ($port in $tcpPorts) {
        $name = "SolStream Sunshine TCP $port"
        if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP `
                -LocalPort $port -Action Allow -Profile Any | Out-Null
            Write-SolStreamLog "Allowed TCP $port" 'ok' -Log $Log
        }
    }
    foreach ($port in $udpPorts) {
        $name = "SolStream Sunshine UDP $port"
        if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol UDP `
                -LocalPort $port -Action Allow -Profile Any | Out-Null
            Write-SolStreamLog "Allowed UDP $port" 'ok' -Log $Log
        }
    }
}

function Install-SolStreamWireGuard {
    [CmdletBinding()]
    param([scriptblock]$Log)

    if (Get-Command wireguard.exe -ErrorAction SilentlyContinue) {
        Write-SolStreamLog 'WireGuard already installed.' 'ok' -Log $Log
        return
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-SolStreamLog 'Installing WireGuard via winget...' 'info' -Log $Log
        if (-not (Invoke-SolStreamWinget -PackageId 'WireGuard.WireGuard' -Log $Log)) {
            Write-SolStreamLog 'WireGuard install failed; get it manually from https://www.wireguard.com/install/' 'warn' -Log $Log
        }
    }
    else {
        Write-SolStreamLog 'winget unavailable; install WireGuard manually from https://www.wireguard.com/install/' 'warn' -Log $Log
    }
}

function Start-SolStreamSunshineService {
    [CmdletBinding()]
    param([scriptblock]$Log)

    $svc = Get-Service -Name SunshineService -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Running') { Start-Service -Name SunshineService }
        Write-SolStreamLog 'Sunshine service is running.' 'ok' -Log $Log
    }
    else {
        Write-SolStreamLog 'Sunshine service not registered yet. Launch Sunshine.exe once to install it.' 'warn' -Log $Log
    }
}

function Invoke-SolStreamInstall {
    <#
    .SYNOPSIS
        Run the full install with the given options. Shared by CLI + GUI.
    #>
    [CmdletBinding()]
    param(
        [int]$NvencPreset = 4,
        [string]$SteamPath = 'C:\Program Files (x86)\Steam\Steam.exe',
        [bool]$EnableFirewall = $true,
        [bool]$EnableWireGuard = $false,
        [scriptblock]$Log
    )

    Write-SolStreamLog 'Starting SolStream install...' 'info' -Log $Log

    $hw = Get-SolStreamHardware
    if (-not $hw.HasNvidia) {
        Write-SolStreamLog 'No NVIDIA GPU detected. SolStream v0.1 requires NVIDIA Ampere or newer.' 'error' -Log $Log
        throw 'No NVIDIA GPU detected.'
    }
    Write-SolStreamLog "GPU: $($hw.GpuModel) (driver $($hw.DriverVersion))" 'ok' -Log $Log

    Install-SolStreamSunshine -Log $Log
    Set-SolStreamSunshineConfig -NvencPreset $NvencPreset -SteamPath $SteamPath -Log $Log
    if ($EnableFirewall) { Add-SolStreamFirewallRules -Log $Log }
    if ($EnableWireGuard) { Install-SolStreamWireGuard -Log $Log }
    Start-SolStreamSunshineService -Log $Log

    Write-SolStreamLog 'Install complete.' 'ok' -Log $Log
    Write-SolStreamLog "Sunshine Web UI: https://$($hw.LanIp):47990" 'ok' -Log $Log
}

Export-ModuleMember -Function `
    Get-SolStreamHardware, `
    Install-SolStreamSunshine, `
    Set-SolStreamSunshineConfig, `
    Add-SolStreamFirewallRules, `
    Install-SolStreamWireGuard, `
    Start-SolStreamSunshineService, `
    Invoke-SolStreamInstall, `
    Write-SolStreamLog
