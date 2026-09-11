# Public sharing and private recovery

Author: Neil Mitchell

| Public Lausudo Suite | Private owner recovery |
| --- | --- |
| Reviewed addon code and permitted media | Exact captured client files and character settings |
| Portable, authored visual presets | Owner's accounts, characters, and SavedVariables |
| Module ZIPs, file manifest, SHA-256 checksums | Private snapshot archives with full-file verification |
| Intended for other players | Accessible only to the owner |

The private backup lives in a separate private repository/storage workflow. Do not add its payloads or receipts to this repository. Keep private recovery documentation with that backup rather than publishing account counts, paths, or manifests here.

**LoginUI is excluded from both uploaded workflows**, including filename variants and archive copies where detected by the private backup tooling. Recreate that private login setup separately after recovery. This public suite never reads or exports it.

Public builds accept repository module folders from `suite.json`; they have no client-source argument. Raw account folders, SavedVariables, configuration, and personal archives are not valid module inputs. The private backup tools remain separate and should never be repurposed as a public export button.

The public package is not a disaster-recovery backup. Installing it cannot recover your personal character settings. Conversely, an exact private snapshot must never be made public to share a UI.

Large client downloads take time according to connection speed. A client-folder backup also does not reinstall Windows, drivers, or settings held elsewhere on the PC.
