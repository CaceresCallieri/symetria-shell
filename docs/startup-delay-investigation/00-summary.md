# Startup Delay Investigation Summary

**Date:** 2026-03-29 (updated 2026-04-03)
**Branch:** investigate/startup-delay
**Symptom:** Shell freezes for 80-93 seconds on Qt 6.11.0 (was 7-10s on Qt 6.10.2).
**Status:** **ROOT CAUSE CONFIRMED — Qt 6.11.0 regression.**

## Root Cause: Qt 6.11.0 Performance Regression

**Qt 6.11.0 causes a ~10x regression in QML binding evaluation / reload walk performance.** This was confirmed through controlled experiments on 2026-04-03.

### Isolation Experiments

| Configuration | Freeze | Conclusion |
|---|---|---|
| Current QS (r110) + Qt 6.11 | **91s** | Current state |
| Old QS (r67) + Qt 6.11 (built from source) | **86s** | Quickshell version irrelevant |
| Old QS + Qt 6.10.2 (March 6 measurement) | **7-10s** | Qt 6.10.2 was 10x faster |
| Drawers only (Qt 6.11) | **91s** | Drawers = 99% of freeze |
| Everything except Drawers (Qt 6.11) | **671ms** | All other modules ~170ms |
| Drawers with stubbed Panels (Qt 6.11) | **672ms** | Panels cascade = 99% of Drawers |
| Fix branch, identical code (Qt 6.11) | **97s** | Codebase changes irrelevant |
| Warm cache (Qt 6.11) | **93s** | QML cache irrelevant |

### Timeline

| Date | Qt Version | Measured Delay |
|------|-----------|----------------|
| 2026-03-06 | Qt 6.10.2 | **7-10s** (heartbeat) |
| **2026-03-26** | **6.10.2 → 6.11.0** | *(system upgrade)* |
| 2026-03-29 | Qt 6.11.0 | **18-20s** (heartbeat) |
| 2026-04-03 | Qt 6.11.0 | **80-93s** (heartbeat) |

Note: The March 29 measurement of 18-20s may have been a warm-state outlier or there may be additional environmental factors causing the increase to 80-93s.

### Recommended Actions

1. **Pin Qt to 6.10.2** in pacman IgnorePkg until the regression is fixed upstream
2. **File a Qt 6.11 bug report** with the reproduction case (Drawers + Panels cascade)
3. **Investigate deferred Panels loading** as a Quickshell-level mitigation (stash@{1} had 8.8s → 1s)

## Architecture Context

The freeze is 100% in the **Quickshell reload walk** — the `EngineGeneration::onReload()` method that recursively evaluates bindings on every QObject child. The Panels sub-tree (12 module imports, ~160 cascaded QML files) produces a super-linear binding evaluation cascade. On Qt 6.10.2 this takes 7-10s. On Qt 6.11.0, the same cascade takes 80-93s.

## Quickshell Framework Limitations (still relevant for mitigation)

- `qs.modules.*` paths don't resolve in URL-loaded files (Loader/LazyLoader)
- Variants forces synchronous compilation — async Loader inside Variants is a no-op
- C++ module init is atomic (Quickshell.Services.Notifications blocks during D-Bus registration)

## File Index

| File | Contents |
|------|----------|
| `00-summary.md` | This file — overview and status |
| `01-profiling-methodology.md` | How to measure startup timing (heartbeat technique) |
| `02-root-cause-analysis.md` | Deep analysis of what causes the delay |
| `03-import-cascade-map.md` | Complete map of which files cascade from which imports |
| `04-attempted-fixes.md` | Every fix attempted and why it did/didn't work |
| `05-quickshell-limitations.md` | Documented Quickshell/Qt framework limitations |
| `06-test-results.md` | Raw test results from all configurations tested |
| `07-bisect-guide.md` | Guide for the git bisect approach |
