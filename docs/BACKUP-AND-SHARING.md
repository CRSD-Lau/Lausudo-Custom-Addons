# Backup and sharing

Author/Creator: Neil Mitchell

Last Modified By: Neil Mitchell

The setup has two separate outputs with different purposes.

## Private recovery

The private backup repository stores recovery tools and private release downloads. A completed snapshot preserves the actual client folder, installed addons and graphics files, and every account and character's local configuration, SavedVariables, macros, and bindings. Personal restore keeps the original identities and folder structure unchanged.

LoginUI files, detected copies, and archives containing LoginUI entries are excluded because they can contain sensitive login information. Private login settings must be recreated separately. A completed backup requires a normal client exit, a consistent capture, full restoration into a separate folder, every restored file's checksum passing, and remote upload verification. A Git clone of the recovery tooling alone is not a downloaded client backup.

No raw client snapshot or personal SavedVariables belong in this public repository, a public branch, or a public release. Folders and branches do not have independent visibility within a GitHub repository.

## Public sharing

The public download should reproduce reviewed UI settings for another player. It must use explicit addon profile handling and the recipient's own account, realm, and characters. Renaming the source account folder or replacing character-name strings across Lua files is not a reliable migration method.

Public exports must remove credentials, private history, and source account/character mappings while retaining reviewed visual settings. Each included addon, profile, font, shader, and other asset must retain its applicable distribution permission and provenance. Personal-use components stay in the private backup or are supplied independently by the recipient.

The existing public suite remains an installer with the differences documented in [Known style gaps](STYLE-GAPS.md). It does not yet constitute a complete snapshot of the private setup. Future profile exports need clean-client and in-game validation before being described as equivalent.

## LoginUI guard

Git ignore rules exclude filenames containing `loginui` in any letter case, including backup variants. The public-tree scanner independently rejects those files even when their contents contain no recognizable credential. Existing archive exclusions also prevent opaque ZIP or other archive copies from entering public releases. Ignore rules alone do not remove files that were already committed; repository history must be checked separately when investigating an exposure.
