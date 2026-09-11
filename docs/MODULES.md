# Module catalog

Author: Neil Mitchell

The machine-readable catalog is `suite.json`. `py -3 tools/suite.py list` shows its IDs and release state. Build one module with `--module <id>`; its repository dependencies are included automatically. External addons remain separate.

| ID | Addon folders | Dependencies | Commands / behavior |
| --- | --- | --- | --- |
| `core` | LausudoSuite | None required; ElvUI or Threat Plates for the respective profile action | `/lausudo`, `/lausudo apply elvui`, `/lausudo apply nameplates`, `/lausudo restore elvui`, `/lausudo restore nameplates` |
| `nameplates` | TidyPlates, TidyPlates_ThreatPlates | None external | `/tptp` opens Threat Plates options. |
| `combat-text` | CrispFCT | Bundles `nameplates` | `/crispfct test`, `/crispfct testin`, `/crispfct on`, `/crispfct off` |
| `fonts` | WarmaneFontPack | Bundled media libraries | Choose fonts through other addons' font selectors. |
| `group-bubbles` | LausudoGroupBubbles | Bundles `fonts`; requires external ElvUI | `/groupbubbles on` or `off`; hides solo/outsider bubbles and conservatively hides ambiguous messages. |
| `paladin-range` | LausudoHoPRange | External ElvUI with UnitFrames and SpellRange APIs | `/hoprange` reports state. Applies to paladins, using Hand of Protection range on raid units. |
| `tank-threat` | LausudoTankTargetThreat | External ElvUI target threat indicator with GLOW style | Red except green at threat status 1. This is a specific tank preference, not the standard threat palette. |

The hub's status checks addon load state. An optional addon can be loaded but inactive because its required ElvUI API, class, or frame style is unavailable; its own status and in-game checks remain necessary.

The three new gameplay modules are disabled by default even in the all-modules ZIP. Enable them individually and restart the client. The core, profiles, and public adaptations are preview functionality; existing fonts, nameplates, and combat text retain their original module versions.

Developer repair/transfer helpers, account-specific performance addon lists, private media loaders, and raw WeakAura libraries are not public suite modules. Future candidates must pass the same provenance, privacy, compatibility, and package checks before being added.
