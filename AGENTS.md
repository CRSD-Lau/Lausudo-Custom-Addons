# Lausudo Suite repository rules

- This is the public suite. The live client and private recovery repository are separate scopes.
- Preserve existing release history, third-party source and licenses, and unrelated dirty worktrees.
- No LoginUI variants, account data, raw SavedVariables, recovery payloads, private media, or client binaries in Git or releases.
- Module inputs come only from `suite.json`. Build outputs belong in ignored `dist/`; use the existing checkout and avoid full client/staging copies.
- Run the Python validation/tests and package verification for tooling changes. Runtime changes require the relevant in-game acceptance before a stable release; label previews honestly.
- Original generated-file author metadata is Neil Mitchell. Global Slack completion and Windows execution rules still apply.
