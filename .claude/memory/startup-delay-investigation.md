---
name: Startup Delay — Root Cause Confirmed
description: Qt 6.11.0 causes ~10x regression in QML binding evaluation (7-10s → 80-93s). Quickshell version and codebase changes are NOT factors. Pin Qt 6.10.2 or wait for upstream fix.
type: project
---

## Root Cause: Qt 6.11.0

**Confirmed 2026-04-03** through controlled experiments: Qt 6.11.0 causes a ~10x regression in QML binding evaluation performance during Quickshell's reload walk.

| Config | Freeze | Proves |
|---|---|---|
| Current QS + Qt 6.11 | 91s | — |
| Old QS (r67, built from source) + Qt 6.11 | 86s | QS version irrelevant |
| Qt 6.10.2 (March 6 measurement) | 7-10s | Qt 6.10.2 was fast |
| Identical code on fix branch + Qt 6.11 | 97s | Codebase irrelevant |
| Drawers with stubbed Panels | 672ms | Panels = 99% of cost |

**Why:** The Panels sub-tree triggers ~160 QML file cascades. The Quickshell reload walk evaluates all bindings super-linearly. Qt 6.11 made this operation ~10x slower.

**How to apply:**
- Pin `qt6-base qt6-declarative qt6-shadertools` to 6.10.2 in `/etc/pacman.conf` IgnorePkg
- Full investigation docs: `docs/startup-delay-investigation/` (8 files)
- Benchmark infrastructure: `~/.config/quickshell/qs-startup-bench/`
- Heartbeat profiler active in shell.qml on `investigate/startup-delay` branch
- Deferred Panels loading (stash) could mitigate even on Qt 6.11 but is blocked by Variants sync compilation
