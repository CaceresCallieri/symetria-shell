---
name: Frozen dark theme — scheme system removed
description: The multi-scheme/variant/light-dark colour system was removed and frozen to a single warm-neutral dark theme (2026-04-11)
type: project
---

The entire multi-scheme colour infrastructure was removed from both the shell and CLI.

**Why:** The complex scheme switching system was inherited from the upstream caelestia fork. It was unused, added fragility, and created a hard dependency on `materialyoucolor` + `PIL` + `dart-sass` + `dconf`. The user decided to simplify to one permanent dark theme rather than consolidate the complexity into the shell.

**How to apply:**
- `Colours.qml` is now dark-only: `light` is hardcoded `false`, no `setMode()`, no preview mode, no scheme/flavour tracking
- The palette loads from `~/.local/state/symmetria/scheme.json` via FileView (unchanged mechanism), seeded from `config/color-scheme.json`
- All scheme switching UI was deleted (ThemeModeSection, ColorSchemeSection, ColorVariantSection, launcher scheme/variant search modes)
- CLI `scheme` subcommand was removed along with all supporting utils (scheme.py, theme.py, colour.py, material/, templates/, schemes/)
- `symmetria wallpaper` no longer does colour extraction or smart mode switching
- GitHub issue #52 was closed by this change (approached differently than originally spec'd — simplification instead of consolidation)
