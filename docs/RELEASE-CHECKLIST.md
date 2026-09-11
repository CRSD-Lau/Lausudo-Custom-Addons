# Release validation

Author: Neil Mitchell

## Automated checks

1. Install the pinned test dependency: `py -3 -m pip install -r requirements-dev.txt`.
2. Run `py -3 tools/suite.py validate` and `py -3 -m unittest discover -s tests -v`.
3. Build the full suite and individual modules. Verify dependency closure, TOC entries, file hashes, licenses, and deterministic rebuilds. The build performs package verification automatically.
4. Inspect the Git diff and public artifact inventory for sensitive or unintended files. Pattern scanning is a backstop, not proof arbitrary content is safe.
5. Confirm the suite version, core TOC, documentation, tag, and release names agree. CI must pass on the exact commit being released.

## In-game acceptance for stable 2.x

- Enable the hub without ElvUI and with optional modules absent; status/help should still work.
- With compatible ElvUI/Threat Plates, apply and restore each profile out of combat. Compare previous settings and check a second character. Repeat apply without losing customizations; test a conflicting profile name.
- Confirm unsupported addon APIs fail gracefully and combat blocks profile changes.
- Test group-bubble behavior in solo, party, and raid; include outsider and identical-text cases. Confirm font choice and behavior after disabling the addon.
- Test learned Hand of Protection range on a paladin, other classes, disconnected/dead raid units, and the configured ElvUI fader.
- Test target threat colors at statuses 0–3, friendly/dead targets, GLOW/non-GLOW, and disabled powerbar offsets.
- Run a normal session with Crisp FCT and nameplates, then verify update/rollback instructions on a separate small addon test setup.

The 2.0.0-alpha.1 preview may be published with these in-game items explicitly outstanding. It must not replace the latest stable release or claim exact visual parity.

## Publishing

The release workflow is manually dispatched with the exact catalog tag (for example `v2.0.0-alpha.1`). It builds and tests on the selected `main` commit, creates a draft GitHub release with ZIPs/checksums, verifies uploaded hashes, then publishes it as a prerelease. It refuses an existing release/tag rather than overwriting another version. Stable promotion requires its own accepted in-game evidence.

Keep generated output in `dist/`. No second extracted package/client is required for routine validation. GitHub CI artifacts expire after seven days. Remove old local version artifacts deliberately when no longer needed; never clear unrelated backup folders as part of a release.
