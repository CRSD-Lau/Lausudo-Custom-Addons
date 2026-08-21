# Manual installation fallback

The PowerShell installer is preferred because it validates the client, records file hashes, and supports conflict-safe uninstall. If it cannot run, use this bounded fallback.

1. Close the target client.
2. Download the release archive and `SHA256SUMS.txt` from the same release.
3. Verify the archive SHA-256 with `Get-FileHash`.
4. Extract the archive into a new empty staging folder outside the client.
5. Review the staged `Interface\AddOns` folders.
6. Copy only the selected addon folders into the client's `Interface\AddOns` directory.
7. Install the pinned ElvUI dependency separately if LausudoStyle is selected.
8. Install the pinned link-only WeakAuras WotLK dependency if Lausudo Visual Core is selected.
9. Enable addons on the character-selection screen and apply the style explicitly in game.

Do not copy `tools`, `docs`, or `manifests` into the client unless you want local documentation. Do not copy any personal configuration into a public repository or release package.

Manual installation creates no receipt. To remove it, close the client and remove only the exact addon folders you manually added. If a folder existed before your copy, restore your own backup instead of deleting it.

DXVK and ReShade are intentionally omitted from this fallback. Follow their official upstream instructions only after making a separate, explicit decision.
