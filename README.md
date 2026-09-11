# Lausudo Suite

A modular collection of Lausudo's addons, visual profiles, and setup tools for **Wrath 3.3.5a**. Install the parts you want, keep your own characters and settings, and add the rest when you need them.

**2.0.0-alpha.1 is a preview.** The new suite hub, profile adapters, and public addon adaptations need in-game acceptance before a stable suite release. The existing 1.x downloads remain available.

[Suite preview and releases](https://github.com/CRSD-Lau/Lausudo-Custom-Addons/releases) · [Install](docs/INSTALL.md) · [Modules](docs/MODULES.md) · [Profiles](docs/PROFILES.md)

![Crisp FCT damage preview on TidyPlates](docs/images/crisp-fct-tidyplates-preview.png)

*Crisp FCT on TidyPlates. This image shows the existing combat-text module, not acceptance evidence for the new suite profiles.*

## Choose your setup

| Part | What it does |
| --- | --- |
| Suite hub | `/lausudo` shows installed modules and offers optional visual profiles with a restore command. |
| Combat text | Crisp FCT attaches outgoing hits to TidyPlates and shows major incoming events. |
| Nameplates | The existing Warmane TidyPlates and Threat Plates backports. |
| Fonts | The existing font pack with redistribution-permitted fonts and their licenses. |
| Group bubbles | Shows native speech bubbles only for your current group, using ElvUI styling. |
| Paladin range | Uses Hand of Protection range for a paladin's ElvUI raid-frame fader. |
| Tank threat | An optional target-frame color convention: red except green at threat status 1. |

The three new gameplay modules are **disabled by default**. Enable only the ones you want at character selection. ElvUI is an external dependency for those modules; it is not included. The suite hub and existing packages can be used independently.

## Get started

1. Download `Lausudo-Suite-2.0.0-alpha.1-all.zip` from the preview release, or choose an individual module ZIP. Individual ZIPs include their bundled dependencies.
2. Close WoW. Follow the [installation and update instructions](docs/INSTALL.md), including preserving the addon folders you will replace.
3. Copy the ZIP's `Interface` folder into your client. No account or character files are installed.
4. Start WoW and choose optional addons at character selection. Use `/lausudo` in game for module status.
5. If wanted, use `/lausudo apply elvui` or `/lausudo apply nameplates`. These select a separate profile; nothing is applied automatically.

## Public sharing and private recovery

This repository is the public suite. Your own character data stays on your machine. Public packages contain reviewed addon code, permitted media, and portable preset instructions. They contain no LoginUI file, raw SavedVariables, account folders, macros, chat history, or client configuration.

The owner's exact client and character recovery backup is maintained separately in private storage. It is not a second mode of this public ZIP. See [backup and sharing](docs/BACKUP-AND-SHARING.md).

The suite does not yet reproduce every detail of the owner's live UI. Its visual baseline keeps the recipient's layout and applies selected font, color, and nameplate settings. Exact layout ports and further character/role presets require separate review and in-game validation.

## Client enhancements

HD patches, graphics wrappers, and other client-level components belong in the broader suite's compatibility documentation. They are not silently copied from the owner's client or bundled with addon releases. See [client enhancements](docs/CLIENT-ENHANCEMENTS.md) for the current boundary.

## Build and contribute

From a source checkout of this repository, Python 3.11 or later builds packages without additional libraries. These build commands are not included in downloaded addon ZIPs:

```powershell
py -3 tools/suite.py list
py -3 tools/suite.py validate
.\tools\Build-Releases.ps1
.\tools\Build-Releases.ps1 -Module combat-text
```

Builds read approved folders listed in [suite.json](suite.json), write directly to ZIPs under ignored `dist/`, and verify every packaged file's hash. Rebuilding the same version/module replaces that artifact. No full client copy or unpacked verification tree is created. Different versions remain until explicitly removed.

See [contributing](CONTRIBUTING.md), [release validation](docs/RELEASE-CHECKLIST.md), and [changelog](CHANGELOG.md). The repository URL stays unchanged so existing links keep working.

## Licenses

Original suite code is MIT licensed to Neil Mitchell. Bundled fonts and third-party addons retain their own licenses and credits; see [third-party notices](THIRD-PARTY-NOTICES.md) and [backport provenance](third_party/README.md). Private Gotham media, client binaries, MPQs, and personal shader collections are not bundled.
