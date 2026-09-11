# Contributing to Lausudo Suite

Author: Neil Mitchell

Use `addons/` for original suite addons, `third_party/addons/` for preserved upstream code, `docs/` for setup and compatibility guidance, `tests/` for offline checks, and `tools/` for source validation and package tooling. `suite.json` is the module/dependency catalog.

New modules need provenance, license, correct interface 30300 TOC, dependency declarations, public-data review, relevant tests, and in-game acceptance. Experimental modules must be labeled as previews and stay opt-in. Preserve upstream names and credits rather than renaming addon folders for branding.

Never develop by overwriting the owner's running client. Work in this repository. Never commit `WTF`, raw SavedVariables, LoginUI, credentials, recovery archives, or private media. Do not execute imported SavedVariables as Lua to obtain settings. Public presets should explicitly select reviewed visual fields and avoid account/character mappings.

Run the automated checks in [the release checklist](docs/RELEASE-CHECKLIST.md). Lua tests run against Lua 5.1 through the pinned Lupa dependency; they do not emulate the renderer or prove in-game behavior.

Use the existing checkout and ignored `dist/` for routine work. Builds stream repository files directly into a ZIP and verify members without extracting them. A task does not need a duplicate full client folder.

Changing the catalog can expand what gets published. Review catalog changes together with the resulting archive inventory. The repository's MIT license covers original code; bundled third-party licenses retain precedence.
