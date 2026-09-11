# Portable visual profiles

Author: Neil Mitchell

The public suite contains a small authored visual baseline, not an export of the owner's SavedVariables. It is intentionally usable on the recipient's own characters.

## Apply and restore

- `/lausudo apply elvui` creates a separate local profile from your current ElvUI profile and changes selected font and color settings.
- `/lausudo apply nameplates` creates a separate Threat Plates profile and applies a compact healthbar and readable font styling.
- `/lausudo restore elvui` and `/lausudo restore nameplates` return to the profile selected before the corresponding apply operation.

Profile operations are blocked in combat. Required addon APIs must be available. The addon does not apply presets at login or on installation.

The suite records its selected profile and previous profile in **per-character** local settings. Each character gets a separate named profile. Existing names are never overwritten: a name collision receives a suffix. Returning to a previously created suite profile keeps your customizations rather than reapplying the baseline. Applying an already-active suite profile is a no-op.

The ElvUI baseline inherits your current frame layout and changes typography plus selected general colors. It does not reconstruct the owner's positions, action bars, WeakAuras, or every addon setting. Safe PT Sans Narrow Bold is used when registered; otherwise the standard Friz Quadrata font is selected.

## What stays private

Account names, character/realm mappings, macros, bindings, chat history, and other local state are never read by the build tools or shipped as an export. Profile names containing the recipient's character and realm are generated only inside their game client.

The in-game operation copies the recipient's own current addon profile locally. It never uploads that copy. Restoring selects an existing local profile; it cannot recover a profile manually deleted through the addon options.

## Further profiles

The next profile work is to port reviewed visual settings from the owner's current setup into explicit templates, with media substitutions and role/class variations where needed. Each template needs a supported-resolution declaration and an in-game before/after comparison. No bulk SavedVariables exporter or arbitrary Lua importer is exposed by this preview.

This preview is not an exact visual replica. Validate apply/restore, character isolation, and actual appearance in game before calling it a stable shared profile.
