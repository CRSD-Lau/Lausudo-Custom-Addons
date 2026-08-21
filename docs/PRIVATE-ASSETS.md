# Private and bring-your-own assets

Safe mode uses PT Sans Narrow and original or built-in Blizzard textures. It is the supported public baseline.

Private mode is detect-only. LausudoStyle asks LibSharedMedia whether one of these names is already registered by the user's installed addons:

- Gotham Narrow Ultra
- Gotham Narrow
- Melli

If a registered name is available, the new profile references that media name in place. LausudoStyle does not locate, open, copy, rename, package, or upload the underlying file. If detection fails, it falls back to safe mode and says so.

ToxiUI media, MartyMods shaders, LUTs, and other personal files are never bundled. There is no automatic downloader for them. Their absence is a supported style gap, not an installation failure.

Users must hold any rights needed to use their own assets. Detecting a local registration does not grant redistribution permission.
