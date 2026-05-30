#Requires -Version 5.1
<#
.SYNOPSIS
    SolStream Windows installer - graphical (WPF) front-end.

.DESCRIPTION
    A windowed install wizard. Detects hardware, lets you pick stream
    options, then runs the install in a background runspace so the window
    stays responsive while progress streams into the log pane.

    Shares all install logic with the CLI via SolStreamInstall.psm1.

    Must run elevated (the install touches the firewall + services). If not
    launched as Administrator, it relaunches itself elevated.

.EXAMPLE
    PS> .\Install-SolStream-GUI.ps1

.NOTES
    Status: Phase 5 scaffolding. Structurally correct WPF, linted in CI,
    but UNTESTED on real Windows hardware. Report issues via the repo.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Self-elevate if not Administrator ----------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$modulePath = Join-Path $PSScriptRoot 'SolStreamInstall.psm1'
Import-Module $modulePath -Force

# --- XAML window definition ---------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SolStream Installer" Height="680" Width="560"
        WindowStartupLocation="CenterScreen"
        Background="#0F1419">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,12">
      <TextBlock Text="SolStream" FontSize="26" FontWeight="Bold" Foreground="#FFA657"/>
      <TextBlock Text="Headless game-streaming server installer" Foreground="#8B949E"/>
    </StackPanel>

    <!-- Detected hardware -->
    <Border Grid.Row="1" Background="#1A212B" CornerRadius="6" Padding="14" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="Detected hardware" FontWeight="Bold" Foreground="#E6EDF3" Margin="0,0,0,6"/>
        <TextBlock x:Name="HwGpu" Foreground="#E6EDF3"/>
        <TextBlock x:Name="HwDriver" Foreground="#8B949E"/>
        <TextBlock x:Name="HwSunshine" Foreground="#8B949E"/>
        <TextBlock x:Name="HwWarning" Foreground="#F85149" TextWrapping="Wrap" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Options -->
    <Border Grid.Row="2" Background="#1A212B" CornerRadius="6" Padding="14" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="Options" FontWeight="Bold" Foreground="#E6EDF3" Margin="0,0,0,8"/>

        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0" Margin="0,0,8,0">
            <TextBlock Text="NVENC preset" Foreground="#8B949E"/>
            <ComboBox x:Name="CmbPreset" SelectedIndex="2">
              <ComboBoxItem Content="P1 - best quality"/>
              <ComboBoxItem Content="P3 - balanced (slow)"/>
              <ComboBoxItem Content="P4 - balanced (recommended)"/>
              <ComboBoxItem Content="P5 - fast"/>
              <ComboBoxItem Content="P7 - fastest"/>
            </ComboBox>
          </StackPanel>
          <StackPanel Grid.Column="1" Margin="8,0,0,0">
            <TextBlock Text="(resolution/refresh set per-client in Moonlight)" Foreground="#8B949E" TextWrapping="Wrap" FontSize="11"/>
          </StackPanel>
        </Grid>

        <TextBlock Text="Steam executable" Foreground="#8B949E" Margin="0,10,0,0"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="TxtSteamPath" Grid.Column="0"
                   Text="C:\Program Files (x86)\Steam\Steam.exe"/>
          <Button x:Name="BtnBrowse" Grid.Column="1" Content="Browse..." Margin="6,0,0,0" Padding="10,2"/>
        </Grid>

        <CheckBox x:Name="ChkFirewall" Content="Add Windows Firewall rules for Sunshine"
                  Foreground="#E6EDF3" Margin="0,10,0,0" IsChecked="True"/>
        <CheckBox x:Name="ChkWireGuard" Content="Install WireGuard for remote streaming"
                  Foreground="#E6EDF3" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Log -->
    <Border Grid.Row="3" Background="#0D1116" CornerRadius="6" Padding="8" Margin="0,0,0,12">
      <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
        <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#3FB950"
                 BorderThickness="0" IsReadOnly="True" FontFamily="Consolas"
                 FontSize="12" TextWrapping="Wrap"/>
      </ScrollViewer>
    </Border>

    <!-- Buttons -->
    <Grid Grid.Row="4">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock x:Name="StatusText" Grid.Column="0" Foreground="#8B949E" VerticalAlignment="Center"/>
      <Button x:Name="BtnInstall" Grid.Column="1" Content="Install"
              Background="#FFA657" Foreground="#0F1419" FontWeight="Bold"
              Padding="22,8" BorderThickness="0"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Bind named controls
$ctl = @{}
foreach ($name in 'HwGpu', 'HwDriver', 'HwSunshine', 'HwWarning', 'CmbPreset',
    'TxtSteamPath', 'BtnBrowse', 'ChkFirewall', 'ChkWireGuard', 'TxtLog',
    'LogScroll', 'StatusText', 'BtnInstall') {
    $ctl[$name] = $window.FindName($name)
}

# --- Populate hardware panel --------------------------------------------
$hw = Get-SolStreamHardware
$ctl.HwGpu.Text = "GPU: $($hw.GpuModel)"
$ctl.HwDriver.Text = if ($hw.DriverVersion) { "Driver: $($hw.DriverVersion)" } else { 'Driver: (none)' }
$ctl.HwSunshine.Text = if ($hw.SunshineInstalled) { "Sunshine: installed" } else { 'Sunshine: not installed (will install)' }

if (-not $hw.HasNvidia) {
    $ctl.HwWarning.Text = 'No NVIDIA GPU detected. SolStream v0.1 requires NVIDIA Ampere or newer. Install disabled.'
    $ctl.BtnInstall.IsEnabled = $false
}

# --- Shared state between UI thread and install runspace ----------------
$sync = [hashtable]::Synchronized(@{
        Lines  = New-Object System.Collections.ArrayList
        Done   = $false
        Failed = $false
    })

# --- Browse button ------------------------------------------------------
$ctl.BtnBrowse.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Steam executable|Steam.exe|All executables|*.exe'
        $dlg.InitialDirectory = 'C:\Program Files (x86)\Steam'
        if ($dlg.ShowDialog()) {
            $ctl.TxtSteamPath.Text = $dlg.FileName
        }
    })

# --- Install button -----------------------------------------------------
$ctl.BtnInstall.Add_Click({
        $ctl.BtnInstall.IsEnabled = $false
        $ctl.StatusText.Text = 'Installing...'

        # Map preset combo index to actual P-number
        $presetMap = @{ 0 = 1; 1 = 3; 2 = 4; 3 = 5; 4 = 7 }
        $preset = $presetMap[$ctl.CmbPreset.SelectedIndex]

        $opts = @{
            NvencPreset     = $preset
            SteamPath       = $ctl.TxtSteamPath.Text
            EnableFirewall  = [bool]$ctl.ChkFirewall.IsChecked
            EnableWireGuard = [bool]$ctl.ChkWireGuard.IsChecked
            ModulePath      = $modulePath
        }

        # Build a runspace that runs the install, logging into $sync.Lines
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('sync', $sync)
        $rs.SessionStateProxy.SetVariable('opts', $opts)

        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
                Import-Module $opts.ModulePath -Force
                $logger = {
                    param($Message, $Level = 'info')
                    [void]$sync.Lines.Add("[$Level] $Message")
                }
                try {
                    Invoke-SolStreamInstall `
                        -NvencPreset $opts.NvencPreset `
                        -SteamPath $opts.SteamPath `
                        -EnableFirewall $opts.EnableFirewall `
                        -EnableWireGuard $opts.EnableWireGuard `
                        -Log $logger
                }
                catch {
                    [void]$sync.Lines.Add("[error] $_")
                    $sync.Failed = $true
                }
                finally {
                    $sync.Done = $true
                }
            })
        $handle = $ps.BeginInvoke()

        # DispatcherTimer drains log lines into the textbox + detects completion
        $script:drained = 0
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $timer.Add_Tick({
                while ($script:drained -lt $sync.Lines.Count) {
                    $line = $sync.Lines[$script:drained]
                    $ctl.TxtLog.AppendText("$line`r`n")
                    $script:drained++
                }
                $ctl.LogScroll.ScrollToEnd()
                if ($sync.Done) {
                    $timer.Stop()
                    if ($sync.Failed) {
                        $ctl.StatusText.Text = 'Install FAILED - see log'
                        $ctl.StatusText.Foreground = '#F85149'
                        $ctl.BtnInstall.IsEnabled = $true
                    }
                    else {
                        $ctl.StatusText.Text = 'Install complete'
                        $ctl.StatusText.Foreground = '#3FB950'
                    }
                    $ps.EndInvoke($handle)
                    $ps.Dispose()
                    $rs.Close()
                }
            })
        $timer.Start()
    })

# --- Show ---------------------------------------------------------------
$window.ShowDialog() | Out-Null
