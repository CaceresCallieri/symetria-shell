---
name: Symmetria Umbrella Decision
description: Symmetria evolves from a single shell project name into a conceptual umbrella for the entire personal computing environment
type: project
---

Symmetria is now the umbrella concept for the user's entire personal computing environment, not just the desktop shell.

**Why:** The file manager, STT, agent dashboard, and shell all share the same philosophy (keyboard-first, beauty-in-function, harmony through proportion) and are already architecturally intertwined within the QuickShell/Symmetria codebase. The name was already organically expanding — the portal is `symmetria_portal.py`, the config is `shell.json` under `~/.config/symmetria/`, and components share M3 theming. Making this explicit aligns naming with reality.

**How to apply:**
- New utilities built within this ecosystem should be named "Symmetria [Domain]" (e.g., Symmetria Files, Symmetria Voice)
- Name the domain, not the tool type — "Files" not "File Manager", "Voice" not "Speech to Text"
- The yazi-frontend project should be referred to as "Symmetria Files" going forward
- The STT system should be referred to as "Symmetria Voice"
- The agent bar/dashboard should be referred to as "Symmetria Agents"
- Future possibilities include a full Symmetria OS (Linux distribution) — the concept is intentionally open-ended

## Decided Structure

```
Symmetria                    ← the concept / the whole environment
├── Symmetria Shell          ← desktop shell (bar, drawers, notifications, lock)
├── Symmetria Files          ← file manager (formerly yazi-frontend)
├── Symmetria Voice          ← STT system
├── Symmetria Agents         ← agent bar / dashboard
└── (future components)      ← clipboard, calculator, etc.
```

## Key Reasoning

- Symmetria means "harmony through proportion" — this scales from visual design to systemic coherence
- The other project names (Kosmos, Vigilia, Magistralia) are atomic — each names one system
- Symmetria is unique in the constellation: it names a *way of computing*, not a single tool
- The decision emerged organically through conversation, not through forced branding — this aligns with the naming philosophy principle that "the correct signal is alignment, not excitement"
