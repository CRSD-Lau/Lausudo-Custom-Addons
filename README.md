# Warmane 3.3.5a Guild Addons

Two self-contained, shareable addons for the Wrath 3.3.5a client used by Warmane.

- **Warmane Font Pack** registers a carefully licensed, curated set of readable fonts with LibSharedMedia.
- **Crisp FCT** renders outgoing damage above compatible TidyPlates using a bundled atlas and shows only selected major incoming events.
- **TidyPlates + Threat Plates** is an unmodified local Warmane 3.3.5a backport bundle required by Crisp FCT.

## Installation

1. Download one of the ZIP files from `dist`.
2. Extract the included `Interface` folder into the root of a **closed** Warmane 3.3.5a client.
3. Enable the addon from the character-selection AddOns screen.

`Crisp FCT` requires TidyPlates. Install the included **TidyPlates + Threat Plates** bundle first. It does not require ElvUI, SharedMedia, or any files from a player's `WTF` directory.

Use `/crispfct test` with a selected target to preview outgoing text. Use `/crispfct testin` to preview the major-incoming-event stream. `/crispfct off` restores native world damage text; `/crispfct on` re-enables Crisp FCT.

## Privacy and release scope

Only the source-controlled files in `addons/`, `licenses/`, documentation, and build tool are included in releases. The build never reads or packages `WTF`, SavedVariables, Config.wtf, account data, screenshots, logs, or any other client-install files.

## Font licensing

The font pack includes only fonts whose included licences allow redistribution. Each font's original licence is in `addons/WarmaneFontPack/licenses/`.

The personal-use Gotham Narrow font and the old Gotham-derived combat-text atlas are intentionally excluded. Crisp FCT uses a newly generated PT Sans Narrow Bold atlas; that font is distributed under the SIL Open Font License, included in `licenses/OFL-PTSansNarrow.txt`.

## Included nameplate backports

`third_party/addons/` contains unmodified copies of the installed Warmane 3.3.5a backports: TidyPlates 6.5.0 and TidyPlates: Threat Plates 5.7. They are distributed as a separate ZIP and contain no SavedVariables data. See `third_party/README.md` for version, provenance, and licence information.
