# ReShade and DXVK boundaries

## ReShade

The repository links to the official ReShade installer. It does not bundle the installer, ReShade binaries, shader collections, textures, LUTs, or third-party preset dependencies.

The modified private preset proposed during the audit is unavailable in v2 until redistribution permission or compatible terms are documented. That missing permission does not block the UI suite. Users receive a source link and no substitute file pretending to reproduce the preset.

## DXVK

DXVK is optional and off by default. Selecting `GraphicsRuntime` explicitly causes the installer to:

1. use the official pinned release URL in the manifest;
2. accept redirects only to GitHub's release-asset host and enforce a 128 MiB streaming limit;
3. stage the archive outside the client;
4. require the pinned SHA-256;
5. reject absolute, traversal, reserved-name, and unsafe Windows archive entries;
6. extract only the pinned x86 D3D9 file; and
7. install it through the same per-file backup and receipt system.

Offline mode never falls back to an unverified local archive. Uninstall preserves a runtime file that changed after installation and reports a conflict.

The project does not claim that DXVK, ReShade, HD patches, or private-server use are approved by Warmane. Optional runtime decisions remain the user's responsibility.
