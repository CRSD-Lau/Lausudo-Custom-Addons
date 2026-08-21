# Installation and receipt safety

## Requirements

- Windows PowerShell 5.1 or PowerShell 7
- Wrath client build 12340 with an x86 `Wow.exe`
- No administrator rights
- The exact target client closed for Install, Repair, or Uninstall
- ElvUI 6.09 installed separately if LausudoStyle will be used
- WeakAuras WotLK 5.21.11 installed separately if Lausudo Visual Core will be used

Use a disposable clean client for release-candidate validation. Do not validate a release workflow against a live personal installation.

## Command surface

```powershell
.\tools\Install-LausudoSuite.ps1 `
  -WowPath '<client-folder>' `
  -Action Audit|Install|Repair|Uninstall `
  -Components UI,ReShadePreset,GraphicsRuntime `
  -Locale enUS `
  [-FullHash] [-Offline] [-WhatIf]
```

`Audit` is the default and makes no changes. Mutating actions require an explicit action and honor PowerShell `ShouldProcess`, including `-WhatIf`.

`UI` is the only default installation component. `GraphicsRuntime` is an explicit DXVK opt-in. `ReShadePreset` currently fails closed because redistribution permission for the proposed private preset has not been documented.

## Validation before writes

The installer resolves the target path and then verifies:

1. the directory exists and is not a reparse point;
2. `Wow.exe` is a valid x86 PE file with build 12340;
3. every source and destination remains inside its expected root;
4. no public package path enters a denied client or private directory;
5. the exact target executable is not running;
6. bundled source hashes still match the precomputed plan; and
7. installer state is neither inside nor above the target client and contains no reparse points; and
8. any download is size-bounded, has its pinned SHA-256, and contains no absolute, traversal, reserved-name, or unsafe Windows archive paths.

The installer never kills a process, requests elevation, renames patches, or changes client configuration.

## Backups and receipts

Only an exact existing file that will be replaced is backed up. State is stored under:

```text
%LOCALAPPDATA%\LausudoWarmaneUISuite\
  Backups\<client-hash>\<timestamp>\
  Receipts\<client-hash>\current.json
```

Each receipt records the relative target, original hash, installed hash, whether a file existed before installation, and the verified backup location. It does not contain account, character, realm, chat, or profile content.

`Repair` recomputes the desired file plan and replaces only planned files. If a user changed an installed file, that current file is backed up before explicit repair.

`Uninstall` acts only on receipt-owned files. It restores a prior file only when the backup exists and still matches its recorded hash. If an installed file changed after installation, the installer preserves it and reports a manual conflict. It leaves unrelated files and directories alone.

Filesystem uninstall does not delete the in-game `Lausudo Style` ElvUI/ThreatPlates profiles or the optional Lausudo WeakAura. Removing those automatically would require reading or editing private SavedVariables, which this installer is intentionally forbidden to do. Remove those profiles or displays from their respective in-game configuration screens if desired.

## Offline mode

Bundled UI components install without network access. `-Offline` prevents a missing DXVK archive from being downloaded. A cached archive is accepted only when it matches the manifest SHA-256.

## Dependencies

ElvUI, ProjectZidras, and WeakAuras are not copied by the suite. Audit reports whether their expected addon roots are present. Install dependencies only from the pinned links in the manifest and review their upstream terms.

## HD audit

Audit compares only the exact HD patch names listed in the HD manifest, their enabled or disabled form, and file sizes. `-FullHash` explicitly opts into reading those listed files to compute hashes. No HD file is downloaded, renamed, moved, or written.
