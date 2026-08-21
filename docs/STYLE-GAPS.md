# Known style gaps and support boundary

The public suite recreates the visual language through supported addon APIs. It does not copy unsupported edits from a local ElvUI, TidyPlates, ProjectZidras, shader, or client tree.

Known differences from the private setup include:

- private Gotham, Melli, and ToxiUI media are replaced in safe mode;
- third-party shader, LUT, and modified ReShade behavior is omitted;
- local ElvUI source patches are not reproduced;
- Threat Plates styling is limited to values exposed through its AceDB runtime profile;
- linked WeakAuras collections are not imported;
- layouts outside 16:9 are not supported, even if forced manually; and
- pixel-perfect results can vary with UI scale, font availability, and upstream addon version.

The reference layout is 2560×1440. The supported secondary target is 1920×1080. Release approval requires in-game review at both resolutions in safe mode and bring-your-own-asset mode.

Any future gap closure must use original work, documented permission, or a compatible upstream license. A private local patch is not itself a redistributable source.
