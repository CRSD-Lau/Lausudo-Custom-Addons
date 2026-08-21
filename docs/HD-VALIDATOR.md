# HD patch validator

The HD manifest describes the expected visual patch state for the Lausudo setup without containing patch bytes. The validator never downloads, enables, disables, renames, moves, or repairs an MPQ.

```powershell
.\tools\Test-LausudoHd.ps1 -WowPath '<client-folder>' -Locale enUS
```

The default check reads only the exact manifest-listed filenames, whether the enabled or `.disabled` form exists, and file length. It does not enumerate unrelated files. Use `-FullHash` only when a complete byte-level check is worth the time:

```powershell
.\tools\Test-LausudoHd.ps1 `
  -WowPath '<client-folder>' `
  -Locale enUS `
  -FullHash
```

Most HD entries currently have no public expected hash. In that case the validator reports the calculated hash without claiming a match. The release cannot treat filename and size agreement as proof of provenance.

HD content remains external. Source links are recorded in the suite manifest for the user's review; the repository makes no claim that those patches or private-server use are approved by Warmane.
