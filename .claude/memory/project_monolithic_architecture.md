---
name: Monolithic architecture decision
description: Symmetria stays monolithic — do not pursue satellite/modular process architecture
type: project
---

Symmetria Shell will remain a monolithic single-process application. The modular satellites architecture (breaking into core + satellite processes) is shelved.

**Why:** The monolithic approach works well for a personal desktop shell. The complexity of multi-process IPC, dual-mode components, and satellite lifecycle management doesn't justify the marginal benefits for this use case.

**How to apply:**
- Do NOT suggest splitting modules into standalone QuickShell configs
- Do NOT continue work on `refactor/modular-satellites` branch
- The branch exists for reference but should not be merged or rebased
- Quality improvements (like DrawerVertical extraction, Nmcli decomposition) should focus on within-process modularity, not process separation
- `docs/architecture-rewrite-plan.md` is historical context, not a roadmap
