# Dependency, source, and license provenance

The versioned suite manifest is authoritative for component distribution mode, source pin, license identifier, destination, and privacy classification.

## Bundled project-owned components

- Crisp FCT — MIT; original project code.
- LausudoStyle — MIT; original visual companion addon.
- Lausudo Visual Core — MIT; one newly authored and manually reviewed visual display.
- WarmaneFontPack wrapper code — MIT; bundled fonts and libraries retain their own terms.

## Bundled third-party addons

TidyPlates and Threat Plates come from `bkader/TidyPlates_WoTLK` commit `a668fc23d329356ad6e808fc084fd0f4094b43e3`. The public v2 trees were compared with that pin after line-ending normalization. TidyPlates is distributed under MIT; Threat Plates is distributed under GPL-3.0-only with complete source and license text.

## Link-only and detect-only components

- ElvUI 6.09 is pinned to tag and commit for compatibility, but its locally modified tree is not copied.
- ProjectZidras is pinned for detection/reference; redistribution is not assumed.
- WeakAuras WotLK 5.21.11 is pinned to its release tag and commit as a link/detect-only dependency; its addon tree and user displays are not copied.
- HD patches remain external and are represented only by expected fingerprints.
- ReShade links to its official installer; binaries and shaders are not bundled.
- Private media is detected by registered runtime name only.
- Existing third-party WeakAuras packs remain link-only unless their authors explicitly clear redistribution.

## Downloaded component

DXVK is the sole automated download. Its manifest record includes an immutable version, official release URL, archive member, and SHA-256. Updating it requires a separate source and hash review.

## Media records

Every bundled font, texture, image, or other binary media path must be covered by `manifests/media-provenance.json` and point to an accompanying license or provenance record. CI rejects uncovered media.

Links identify sources; they do not imply endorsement, compatibility beyond the tested target, or permission beyond the stated license.
