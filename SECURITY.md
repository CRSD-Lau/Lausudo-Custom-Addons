# Security policy

## Reporting

Do not open a public issue containing a password, token, account identifier, character mapping, private path, SavedVariables content, screenshot with private UI, or other sensitive material. Use GitHub's private vulnerability-reporting channel when enabled, or contact the repository owner privately through the account listed on the project.

Include the smallest synthetic reproduction possible. Do not upload a live client folder or personal configuration.

## Supported versions

Security and privacy fixes target the latest v2 release candidate and eventual v2 stable line. Immutable v1 release assets are preserved for integrity but are not the recommended installer path.

## Scope

High-priority reports include path traversal, reparse-point escape, receipt ownership errors, unsafe uninstall behavior, hash bypass, archive extraction outside staging, privacy scanner bypass, exporter allowlist bypass, and accidental public packaging of denied files.

The project does not request credentials and does not provide server-policy evasion, anti-detection, or bypass functionality.
