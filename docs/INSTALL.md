# Install, update, and remove

Author: Neil Mitchell

## Requirements

- Wrath 3.3.5a, interface version 30300. This suite is not for current retail WoW.
- ElvUI only for its visual profile and the group-bubbles, paladin-range, and tank-threat modules. Use a compatible 3.3.5a version you already trust; current retail builds are incompatible.
- Python 3.11+ is needed only when building from source. Downloaded ZIPs need no Python or installer application.

## First installation

1. Choose the all-modules preview or an individual module archive on the repository's Releases page. Preview means the new modules still need in-game acceptance.
2. Compare the ZIP's SHA-256 with its matching `.sha256` file using `Get-FileHash -LiteralPath '<downloaded zip>' -Algorithm SHA256`. The checksum detects a damaged download; obtain both from the trusted release.
3. Close the exact WoW client you will modify.
4. Extract the ZIP's `Interface` folder into that client's root. The result must be `Interface\AddOns\LausudoSuite\LausudoSuite.toc` for the hub, with other selected addon folders beside it.
5. Start WoW. At character selection, enable the optional modules you want. Group bubbles, paladin range, and tank threat start disabled.
6. Log in and run `/lausudo status` if you installed the hub. See [module commands](MODULES.md).

Do not copy the whole repository into the client. Do not install anything into `WTF`. The package manifest identifies the exact files included in your chosen download.

## Updating an existing installation

Close WoW first. Inspect `package-manifest.json` for the addon folders in the new ZIP. Preserve one previous copy of **only those addon folders** outside `Interface\AddOns`, then replace those folders with the new package. Replacing whole addon folders avoids leaving obsolete source files behind. Leave all other addons and `WTF` untouched.

Retain that small previous copy until the update passes your in-game check, then remove it when you no longer need rollback. Do not keep making full client copies for addon updates. Never delete all of `Interface\AddOns` or `WTF` as part of this process.

The suite currently uses manual updates. It does not download, install, or enable code automatically.

## Inspect before changing anything

The optional read-only PowerShell helper reports installed addon TOCs and dependencies:

```powershell
.\tools\Inspect-Client.ps1 -ClientPath 'D:\Your WoW Client'
```

It does not open account data, SavedVariables, LoginUI, or client configuration. It verifies presence, not compatibility or in-game behavior.

## Roll back or remove

- For a visual profile change, use `/lausudo restore elvui` or `/lausudo restore nameplates` before removing the hub. You can also select the previous profile in that addon's options.
- Disable optional modules at character selection and restart WoW to remove their runtime hooks.
- To roll back addon code, close WoW and restore only the addon folders saved before the update.
- To remove the suite, close WoW and remove only its addon folders. Keep bundled dependencies if other addons use them. Leave `WTF` intact; deleting an addon folder does not erase its saved settings.

Group bubbles takes control of ElvUI's bubble handling while loaded. After disabling it, check your normal chat-bubble preference and turn bubbles back on if desired. The suite does not claim to undo every option an optional addon changes.
