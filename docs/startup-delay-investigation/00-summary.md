# Startup Delay Investigation Summary

**Date:** 2026-03-29 (confirmed 2026-04-04)
**Branch:** investigate/startup-delay
**Status:** **ROOT CAUSE CONFIRMED — Qt 6.11.0 performance regression**

## Root Cause: Qt 6.11.0

Qt 6.11.0 causes a **~4x regression** in QML binding evaluation during Quickshell's reload walk. This was confirmed by downgrading Qt to 6.10.2 on the same system, same code, same day:

| Qt Version | Quickshell | Freeze | Notes |
|---|---|---|---|
| Qt 6.10.2 | r67 (March 6 measurement) | **7-10s** | Original baseline |
| Qt 6.11.0 | r110 | **91s** | Current installed version |
| Qt 6.11.0 | r67 (built from source) | **86s** | Quickshell version NOT a factor |
| **Qt 6.10.2** | **r125 (rebuilt from AUR)** | **22s** | **Confirmed: Qt is the cause** |

### Why 22s and not 7-10s?

The 22s on Qt 6.10.2 (April 4) vs 7-10s (March 6) is because Quickshell itself went from r67 → r125 (58 new commits). So there IS some Quickshell growth contribution (~2-3x), but the **dominant factor** is Qt 6.11 (4x regression on top of that).

### Isolation Experiments (2026-04-03/04)

| Test | Freeze | Conclusion |
|---|---|---|
| Bare Quickshell (no modules) | 504ms | Framework baseline |
| All imports, zero instantiation | 508ms | Imports are free |
| All modules EXCEPT Drawers | 671ms | Other modules = ~170ms total |
| Drawers only | **91s** | Drawers = 99% of freeze |
| Drawers with Panels stubbed | 672ms | Panels = 99% of Drawers |
| fix/deferred-panel-loading branch | 97s | Code changes NOT a factor |
| Warm cache (no cache clear) | 93s | QML cache NOT a factor |
| Full shell minus notifications | 93s | D-Bus blocker fully overlapped |

### Distribution Status (April 2026)

**Arch Linux is the only major distro shipping Qt 6.11.0.** Caelestia's userbase is ~70% NixOS (Qt ~6.10.1). This is why no one else has reported the issue yet.

### Suspected Qt 6.11 Changes

1. **"Do not store type references for properties"** — `QQmlPropertyCache` internal change enabling cyclic type references. May make property resolution more expensive during binding cascades.
2. **Property shadowing runtime enforcement** — new `virtual`/`override`/`final` keywords add runtime checking. Our logs show `qt.qml.propertyCache.append: Member ... overrides a member of the base object` warnings.

### Workaround Applied

Qt pinned to 6.10.2 via `IgnorePkg` in `/etc/pacman.conf`. Quickshell and Symmetria C++ plugin rebuilt from source against 6.10.2.

### Recommended Actions

1. **File Quickshell issue** — outfoxxed can reproduce on Arch and create a targeted Qt reproduction
2. **File Qt bug** — draft at `qt-bug-report-draft.md` with all data
3. **Implement deferred Panels loading** — proven approach (8.8s → 1.0s) that sidesteps the reload walk bottleneck regardless of Qt version
4. **Architecture rewrite** — long-term plan at `docs/architecture-rewrite-plan.md`

## File Index

| File | Contents |
|------|----------|
| `00-summary.md` | This file — overview and confirmed root cause |
| `01-profiling-methodology.md` | How to measure startup timing (heartbeat technique) |
| `02-root-cause-analysis.md` | Deep analysis of what causes the delay |
| `03-import-cascade-map.md` | Complete map of which files cascade from which imports |
| `04-attempted-fixes.md` | Every fix attempted and why it did/didn't work |
| `05-quickshell-limitations.md` | Documented Quickshell/Qt framework limitations |
| `06-test-results.md` | Raw test results from all configurations tested |
| `07-bisect-guide.md` | Guide for the git bisect approach (superseded by Qt confirmation) |
| `qt-bug-report-draft.md` | Draft bug report for bugreports.qt.io |
