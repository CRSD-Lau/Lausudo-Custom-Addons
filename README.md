# Lausudo Custom Addons

Clean, shareable UI building blocks for the Wrath 3.3.5a client used by Warmane.

[Download the latest release](https://github.com/CRSD-Lau/Lausudo-Custom-Addons/releases/latest) · [Browse the source](https://github.com/CRSD-Lau/Lausudo-Custom-Addons)

![Crisp FCT damage preview on TidyPlates](docs/images/crisp-fct-tidyplates-preview.png)

*Crisp FCT on TidyPlates: high-contrast normal and critical hits remain readable in a busy scene.*

## What is included

| Download | What it provides | Needed? |
| --- | --- | --- |
| **TidyPlates + Threat Plates** | Warmane 3.3.5a nameplate backports. TidyPlates supplies the exact target identity Crisp FCT needs. | Required for Crisp FCT |
| **Crisp FCT** | Large, plate-attached outgoing hits, vertical crits, and filtered major incoming events. | Optional |
| **Warmane Font Pack** | A curated, redistribution-safe collection of LibSharedMedia fonts. | Optional |

## Install

1. Close World of Warcraft.
2. Download and extract **TidyPlates + Threat Plates** into your Warmane client folder.
3. Extract **Crisp FCT** and, if wanted, **Warmane Font Pack** to that same folder.
4. The extracted folders must end up under `Interface\AddOns\`.
5. Enable the addons at the character-selection AddOns screen, then log in.

Each release ZIP already contains an `Interface` folder, so extracting it into the client root produces the correct structure.

## Crisp FCT

**Compatibility:** Crisp FCT requires **TidyPlates**. Threat Plates is supported when it runs on TidyPlates. This dependency allows each hit to stay with the correct creature instead of guessing when multiple enemies share a name.

| Command | Result |
| --- | --- |
| `/crispfct test` | Preview outgoing text on your selected target. |
| `/crispfct testin` | Preview the major incoming-event stream. |
| `/crispfct on` | Enable Crisp FCT. |
| `/crispfct off` | Disable it and restore native world damage text. |

## Fonts and licensing

The font pack contains only fonts whose included licences allow redistribution; each original licence is preserved in `addons/WarmaneFontPack/licenses/`.

The personal-use Gotham Narrow font and the original Gotham-derived combat-text atlas are not included. Crisp FCT instead uses a bundled PT Sans Narrow Bold atlas licensed under the SIL Open Font License.

TidyPlates and Threat Plates are included as untouched Warmane 3.3.5a backports. Their version, provenance, and upstream licence details are in [third_party/README.md](third_party/README.md).

## Privacy

No `WTF` directory, SavedVariables file, account data, configuration, screenshots folder, logs, or personal UI profile is included in a release. The showcased image above was provided explicitly for this repository; it is not copied from the client installation.

## Building from source

Run the following from PowerShell at the repository root:

```powershell
.\tools\Build-Releases.ps1
```

The script rebuilds the release ZIPs and `SHA256SUMS.csv` in `dist/`.
