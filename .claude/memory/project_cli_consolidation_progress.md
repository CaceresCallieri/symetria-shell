---
name: CLI consolidation progress tracker
description: Tracks which GitHub issues for CLI→shell consolidation have been completed (2026-04-11)
type: project
---

CLI consolidation effort status as of 2026-04-11:

| Issue | Title | Status | Approach |
|-------|-------|--------|----------|
| #50 | Remove redundant clipboard CLI subcommand | **DONE** | Deleted clipboard.py + references |
| #51 | Remove redundant screenshot CLI subcommand | **DONE** | Deleted screenshot.py + references |
| #52 | Consolidate scheme management into the shell | **DONE** | Simplified: froze to single dark theme instead of consolidating |
| #53 | Consolidate wallpaper management into the shell | Open | Still needs work |
| #54 | Resolve split recording responsibility | Open | Still needs work |
| #55 | Document and formalize CLI→shell migration plan | Open | Tracking issue, depends on #53-#54 |

**How to apply:** When working on remaining issues, note that #52 was solved by simplification (removing the feature) rather than consolidation (moving it to the shell). The same approach may or may not be appropriate for #53/#54 — ask the user.

Remaining CLI subcommands: shell, toggle, record, emoji, wallpaper, resizer
