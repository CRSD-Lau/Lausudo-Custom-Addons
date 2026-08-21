# v2 release checklist

## Automated gates

- [ ] Lua 5.1 parser passes for project and bundled addon source.
- [ ] Pester tests pass under Windows PowerShell 5.1 and PowerShell 7.
- [ ] JSON manifests pass their schemas.
- [ ] Public-tree privacy and provenance scanner passes.
- [ ] Gitleaks passes over full history and the generated release tree.
- [ ] License inventory and standalone notices are complete.
- [ ] Every WeakAuras custom-code file has a current manual-review hash.
- [ ] Every release archive builds twice with identical SHA-256.
- [ ] Checksums and machine-readable manifest are included.
- [ ] GitHub artifact attestation succeeds for candidate assets.

## Disposable-client gates

- [ ] Audit makes no writes.
- [ ] UI install, repair, and uninstall complete on a clean build-12340 x86 client.
- [ ] Pre-existing files are restored from verified backups.
- [ ] Files changed after install are preserved as conflicts.
- [ ] Offline UI install succeeds.
- [ ] Offline DXVK install fails closed without a verified cache.
- [ ] Hash mismatch and archive traversal fixtures fail closed.
- [ ] Missing ElvUI, WeakAuras, and Threat Plates dependencies are reported safely.
- [ ] Private-media absence falls back to safe media.
- [ ] HD state mismatches are reported without mutation.

## Human gates

- [ ] License/provenance review complete.
- [ ] Privacy review complete.
- [ ] Every proposed screenshot reviewed at full frame.
- [ ] In-game visual QA complete at 1920×1080 safe mode.
- [ ] In-game visual QA complete at 2560×1440 safe mode.
- [ ] In-game visual QA complete at both resolutions with detected private assets.
- [ ] User visual signoff recorded.

## Sequence

1. Merge implementation only after review on the feature pull request.
2. Publish `v2.0.0-rc.1` under the current repository name.
3. Complete every automated, disposable-client, and human gate above.
4. Rename the repository once; update remotes and documentation; do not reuse the old name.
5. Recheck redirected Git and web URLs, release assets, branch rules, secret scanning, push protection, and attestations.
6. Preserve all v1 tags and assets, then publish `v2.0.0`.

Failure to clear the private ReShade preset leaves that component unavailable; it does not block the suite release.
