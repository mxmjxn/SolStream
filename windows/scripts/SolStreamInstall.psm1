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

function Get-SolStreamSunshineConfigDir {
    <#
    .SYNOPSIS
        Find the directory Sunshine actually reads its config from.
    .DESCRIPTION
        On Windows, Sunshine installed as a service reads from
        <install>\config\, NOT %APPDATA%. Discover it from the running
        process, then the command, then the service binary, then the
        default install path.
    #>
    [CmdletBinding()]
    param()

    $exe = $null
    $proc = Get-Process sunshine -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { $exe = $proc.Path }
    if (-not $exe) {
        $cmd = Get-Command sunshine.exe -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source }
    }
    if ($exe) {
        $dir = Join-Path (Split-Path $exe -Parent) 'config'
        if (Test-Path $dir) { return $dir }
    }

    $svc = Get-CimInstance Win32_Service -Filter "Name='SunshineService'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName) {
        $binPath = $svc.PathName.Trim('"')
        # ...\tools\sunshinesvc.exe -> install root -> \config
        $root = Split-Path (Split-Path $binPath -Parent) -Parent
        $dir = Join-Path $root 'config'
        if (Test-Path $dir) { return $dir }
    }

    $default = 'C:\Program Files\Sunshine\config'
    if (Test-Path $default) { return $default }
    return $null
}

function Set-SolStreamSunshineConfig {
    <#
    .SYNOPSIS
        Apply tuning to Sunshine's real config dir (NOT %APPDATA%).
    .DESCRIPTION
        Merges our NVENC tuning into the existing sunshine.conf (preserving
        any web-UI-set keys like the admin credentials), and writes apps.json
        using Sunshine's native steam:// format so it doesn't depend on a
        hardcoded Steam.exe path.
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

    $cfgDir = Get-SolStreamSunshineConfigDir
    if (-not $cfgDir) {
        Write-SolStreamLog 'Could not locate Sunshine config dir; is Sunshine installed? Skipping config.' 'warn' -Log $Log
        return
    }
    Write-SolStreamLog "Sunshine config dir: $cfgDir" 'info' -Log $Log

    # --- sunshine.conf: merge our tuning, preserve everything else ---
    $confPath = Join-Path $cfgDir 'sunshine.conf'
    $settings = [ordered]@{}
    if (Test-Path $confPath) {
        foreach ($line in Get-Content $confPath) {
            if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
                $settings[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    $settings['encoder'] = 'nvenc'
    $settings['nvenc_preset'] = "$NvencPreset"
    $settings['nvenc_twopass'] = 'disabled'
    $settings['nvenc_realtime_hags'] = 'enabled'
    $settings['hevc_mode'] = "$HevcMode"
    $settings['min_threads'] = "$MinThreads"
    $settings['fec_percentage'] = "$FecPercentage"
    $settings['origin_web_ui_allowed'] = 'lan'
    $confLines = $settings.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }
    Set-Content -Path $confPath -Value $confLines -Encoding ascii -Force
    Write-SolStreamLog "Applied tuning to $confPath" 'ok' -Log $Log

    # --- apps.json: Desktop + Steam Big Picture (steam:// url) + Quit game ---
    # Use Sunshine's native steam:// format (no hardcoded Steam.exe path).
    # $_ in the quit cmd stays literal via the single-quoted string.
    $quitCmd = 'Get-Process | Where-Object { $_.Path -like ''*steamapps*'' } | Stop-Process -Force'
    $appsObj = [ordered]@{
        env  = [ordered]@{}
        apps = @(
            [ordered]@{ name = 'Desktop'; 'image-path' = 'desktop.png' },
            [ordered]@{
                name          = 'Steam Big Picture'
                cmd           = 'steam://open/bigpicture'
                'prep-cmd'    = @([ordered]@{ do = ''; undo = 'steam://close/bigpicture' })
                'auto-detach' = $true
                'wait-all'    = $true
                'image-path'  = 'steam.png'
            },
            [ordered]@{
                name          = 'Quit current game'
                cmd           = @('powershell', '-NoProfile', '-Command', $quitCmd)
                'auto-detach' = $false
                'wait-all'    = $true
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

function Install-SolStreamSteam {
    <#
    .SYNOPSIS
        Install Steam via winget if it isn't already present.
    .OUTPUTS
        The resolved Steam.exe path (existing or freshly installed).
    #>
    [CmdletBinding()]
    param([scriptblock]$Log)

    $defaultPath = 'C:\Program Files (x86)\Steam\Steam.exe'
    if (Test-Path $defaultPath) {
        Write-SolStreamLog 'Steam already installed.' 'ok' -Log $Log
        return $defaultPath
    }
    # Maybe it's installed elsewhere - check the registry
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
    if ($reg -and $reg.InstallPath -and (Test-Path (Join-Path $reg.InstallPath 'Steam.exe'))) {
        $p = Join-Path $reg.InstallPath 'Steam.exe'
        Write-SolStreamLog "Steam already installed at $p" 'ok' -Log $Log
        return $p
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-SolStreamLog 'Installing Steam via winget...' 'info' -Log $Log
        if (Invoke-SolStreamWinget -PackageId 'Valve.Steam' -Log $Log) {
            return $defaultPath
        }
    }
    Write-SolStreamLog 'Could not install Steam automatically. Install it from https://store.steampowered.com and re-run.' 'warn' -Log $Log
    return $defaultPath
}

function Install-SolStreamVirtualDisplay {
    <#
    .SYNOPSIS
        Install a virtual display driver so a fully headless host (no monitor)
        has a display surface for Sunshine to capture.
    .DESCRIPTION
        Uses the community Virtual-Display-Driver (an IDD-based virtual
        monitor). Skips if a virtual display is already present. This is the
        Windows analogue of the synthetic-EDID work on the Linux side.

        EXPERIMENTAL: installs a third-party kernel display driver. Only needed
        on truly headless boxes; machines with a real monitor or an HDMI dummy
        plug don't need it.
    #>
    [CmdletBinding()]
    param(
        [string]$ReleaseUrl = 'https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/latest/download/Virtual.Display.Driver-x64.zip',
        [scriptblock]$Log
    )

    $existing = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'Virtual Display|IddSample|MTT|Idd' }
    if ($existing) {
        Write-SolStreamLog 'Virtual display driver already present.' 'ok' -Log $Log
        return
    }

    Write-SolStreamLog 'Installing virtual display driver (headless display surface)...' 'info' -Log $Log
    $work = Join-Path $env:TEMP 'solstream-vdd'
    $zip = Join-Path $env:TEMP 'solstream-vdd.zip'
    try {
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        Invoke-WebRequest -Uri $ReleaseUrl -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $work -Force

        $inf = Get-ChildItem -Path $work -Recurse -Filter '*.inf' | Select-Object -First 1
        if (-not $inf) {
            Write-SolStreamLog 'Virtual display package had no .inf; skipping. Install manually if you need headless.' 'warn' -Log $Log
            return
        }
        # Trust the driver's catalog cert so pnputil can install it unattended
        $cert = Get-ChildItem -Path $work -Recurse -Filter '*.cer' | Select-Object -First 1
        if ($cert) {
            Import-Certificate -FilePath $cert.FullName -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
            Import-Certificate -FilePath $cert.FullName -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
        }
        $result = pnputil /add-driver $inf.FullName /install 2>&1
        Write-SolStreamLog "pnputil: $($result -join '; ')" 'info' -Log $Log
        Write-SolStreamLog 'Virtual display driver installed. A reboot may be needed for it to enumerate.' 'ok' -Log $Log
    }
    catch {
        Write-SolStreamLog "Virtual display install failed: $_" 'warn' -Log $Log
        Write-SolStreamLog 'Headless capture will not work until a virtual display or dummy plug is present.' 'warn' -Log $Log
    }
    finally {
        Remove-Item $zip -ErrorAction SilentlyContinue
        Remove-Item $work -Recurse -ErrorAction SilentlyContinue
    }
}

function Start-SolStreamSunshineService {
    [CmdletBinding()]
    param([scriptblock]$Log)

    $svc = Get-Service -Name SunshineService -ErrorAction SilentlyContinue
    if ($svc) {
        # Ensure it survives reboots
        Set-Service -Name SunshineService -StartupType Automatic -ErrorAction SilentlyContinue
        if ($svc.Status -eq 'Running') {
            # Restart so the freshly-written sunshine.conf is re-read.
            Restart-Service -Name SunshineService -Force
            Write-SolStreamLog 'Sunshine service restarted to load new config (startup: Automatic).' 'ok' -Log $Log
        }
        else {
            Start-Service -Name SunshineService
            Write-SolStreamLog 'Sunshine service started (startup: Automatic).' 'ok' -Log $Log
        }
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
        [bool]$InstallSteam = $true,
        [bool]$InstallVirtualDisplay = $false,
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

    # Install Steam if requested; use the resolved path for apps.json so we
    # don't hardcode a location that may not exist.
    $resolvedSteam = $SteamPath
    if ($InstallSteam) {
        $resolvedSteam = Install-SolStreamSteam -Log $Log
    }

    if ($InstallVirtualDisplay) {
        Install-SolStreamVirtualDisplay -Log $Log
    }

    Set-SolStreamSunshineConfig -NvencPreset $NvencPreset -SteamPath $resolvedSteam -Log $Log
    if ($EnableFirewall) { Add-SolStreamFirewallRules -Log $Log }
    if ($EnableWireGuard) { Install-SolStreamWireGuard -Log $Log }
    Start-SolStreamSunshineService -Log $Log

    Write-SolStreamLog 'Install complete.' 'ok' -Log $Log
    Write-SolStreamLog "Sunshine Web UI: https://$($hw.LanIp):47990" 'ok' -Log $Log
    if (-not $InstallVirtualDisplay) {
        Write-SolStreamLog 'Note: for a fully headless box (no monitor), re-run with the virtual-display option or attach an HDMI dummy plug.' 'info' -Log $Log
    }
}

Export-ModuleMember -Function `
    Get-SolStreamHardware, `
    Get-SolStreamSunshineConfigDir, `
    Install-SolStreamSunshine, `
    Install-SolStreamSteam, `
    Install-SolStreamVirtualDisplay, `
    Set-SolStreamSunshineConfig, `
    Add-SolStreamFirewallRules, `
    Install-SolStreamWireGuard, `
    Start-SolStreamSunshineService, `
    Invoke-SolStreamInstall, `
    Write-SolStreamLog
