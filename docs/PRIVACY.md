# Privacy and threat model

This project assumes a live game installation may contain passwords, tokens, account identifiers, character and realm mappings, chat, combat history, private messages, screenshots, local paths, and licensed personal media. A clean secret scan does not make those surfaces safe to publish.

## Hard boundary

The live client is never a repository, build workspace, download staging area, or release source. The public project denylist is case-insensitive and includes client configuration, account state, SavedVariables, patch data, backups, caches, logs, errors, client screenshot directories and unreviewed captures, dumps, executables, libraries, disabled patches, temporary files, and committed archives.

The installer does not enumerate or open personal configuration. It plans from the public manifest and bundled repository sources. The only client state it inspects is:

- `Wow.exe` PE metadata needed to validate x86 build 12340;
- exact addon roots listed in the component manifest;
- exact target files it may install, repair, or uninstall; and
- exact HD filenames listed in the HD manifest, with optional user-requested hashing.

It never reads chat, macros, bindings, account folders, SavedVariables, configuration text, logs, screenshots, or unlisted client data.

## Public-tree scanner

CI rejects:

- denied path segments and risky file extensions;
- files larger than GitHub's 100 MiB limit;
- binary media outside an approved provenance root;
- unreviewed or hash-stale WeakAuras Lua;
- concrete local machine paths;
- credential-like assignments;
- concrete private configuration paths; and
- reparse-like entries.

Gitleaks scans full history and the generated release tree. The structural scanner is intentionally independent because identity or history data may not look like a conventional secret.

## Developer-only exporter

`Export-LausudoVisualProfile.ps1` is the only tool that accepts personal profile state, and it requires one explicit input file, one exact profile name, and one explicit output path. It never searches for configuration automatically.

The exporter parses data without executing Lua, selects allowlisted visual fields, substitutes restricted media, rejects identity/history/gameplay keys and local paths, and writes only to ignored private staging or outside the repository. Unknown or unsupported expressions fail closed. Exported output still requires human review before any field is hand-translated into public addon code.

## Screenshot gate

Every proposed screenshot requires full-frame human review for chat, names, guild and realm details, account information, calendar entries, private messages, and identifying overlays. Cropping is not a substitute for reviewing the source image. No screenshot collector exists in this project.
