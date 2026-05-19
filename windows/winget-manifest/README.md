# winget manifest for SolStream

Eventually we'd PR a manifest to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) so users can install via:

```powershell
winget install LizardByte.SolStream
```

(Or whatever publisher namespace we use — TBD.)

The manifest hasn't been generated yet because:

1. The Windows installer is still scaffolding-level (see `../scripts/Install-SolStream.ps1`)
2. winget manifests need an installer EXE/MSI with code-signing for trust
3. We haven't decided on the binary distribution form (PS1 + zip? wrapped MSI? Chocolatey-style nupkg?)

When ready, the manifest structure will look like:

```yaml
# manifest.yaml (winget v1.6 schema)
PackageIdentifier: SolStream.SolStream
PackageVersion: 0.1.0
PackageLocale: en-US
Publisher: SolStream
PackageName: SolStream
License: MIT
ShortDescription: Headless game-streaming server installer
Installers:
  - Architecture: x64
    InstallerType: exe
    InstallerUrl: https://github.com/mxmjxn/SolStream/releases/download/v0.1.0/SolStream-Installer.exe
    InstallerSha256: <sha>
    InstallerSwitches:
      Silent: /S
      SilentWithProgress: /S
ManifestType: version
ManifestVersion: 1.6.0
```

Tracking issue: [TODO once repo issues are enabled]
