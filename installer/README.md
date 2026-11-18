# Khan Baba POS — Windows installer and updater

## Installer design

The native Windows desktop app uses a per-user x64 Inno Setup installer. It installs under:

`%LOCALAPPDATA%\Programs\KhanBabaPOS`

Business data remains separate under:

`%LOCALAPPDATA%\KhanBabaPOS\Data`

The installer explicitly retains the Data, Backups and Updates directories on uninstall. The live SQLite database, active-database pointer, backups, DPAPI credentials and Google Drive tokens are not stored in the install directory and must not be removed during an upgrade or uninstall.

## Build the installer locally

Prerequisites: .NET 10 SDK, Inno Setup 6.4 or later, and a Windows x64 build environment.

From the repository root:

```powershell
dotnet restore desktop-wpf/KhanBabaPos.Wpf.csproj
dotnet test desktop-wpf.Tests/KhanBabaPos.Wpf.Tests.csproj -c Release
dotnet publish desktop-wpf/KhanBabaPos.Wpf.csproj -c Release -r win-x64 --self-contained true -o artifacts/publish/win-x64
ISCC.exe /DAppVersion=1.0.1.0 installer/KhanBabaPOS.iss
```

The output is written to `artifacts/installer/KhanBabaPOS-Setup-x64.exe`. Do not distribute an unsigned installer.

## Windows versioning

The WPF application, AssemblyVersion, FileVersion, installer AppVersion, GitHub Windows release tag and `khan-baba-release.json` version must use the same four-part version (for example, `1.0.1.0`). Increment the patch component for each Windows maintenance update (for example, `1.0.2.0`); use the minor or major component for larger feature or compatibility releases.

Android CI tags such as `v1.0.0-build225` are parsed safely but their build suffix is not a Windows version. A three-part product version is normalized to four parts before comparing it with the installed Windows AssemblyVersion.

## Update release manifest

A GitHub release must include both the installer and a `khan-baba-release.json` asset:

```json
{
  "version": "1.0.1.0",
  "installerAsset": "KhanBabaPOS-Setup-x64.exe",
  "sha256": "<64-character SHA-256 of the installer>",
  "publisherThumbprint": "<40-character SHA-1 certificate thumbprint>"
}
```

The in-app updater downloads the manifest and installer from the latest public GitHub release, verifies the SHA-256, checks Windows Authenticode status, and compares the signer thumbprint to a pinned publisher thumbprint before launching the installer silently.

**Updater installation is intentionally disabled** until the owner supplies the production code-signing certificate and its thumbprint is pinned in `NativeUpdateService.TrustedPublisherThumbprint`. The installer and update feed must be signed by that same trusted publisher. Do not replace the empty pin with a guessed or self-signed thumbprint.

## Release safety gates

- Build and test on Windows x64.
- Sign the installer with the approved production certificate.
- Verify the Authenticode signature and the release manifest SHA-256.
- Test a clean per-user install, in-place upgrade, rollback/reinstall, and uninstall.
- Verify existing SQLite v18 database, active database pointer, backups, DPAPI staff credentials and Drive tokens survive upgrades and remain after uninstall.
- Obtain owner acceptance before publishing a production release.
