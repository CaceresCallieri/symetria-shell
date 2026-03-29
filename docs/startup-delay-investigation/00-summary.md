# Startup Delay Investigation Summary

**Date:** 2026-03-29
**Branch:** fix/deferred-panel-loading
**Symptom:** Shell freezes for ~18-20 seconds after "Configuration Loaded" before becoming responsive.
**Status:** Root causes identified. Fix requires Quickshell framework changes or a bisect-based approach to find the regression commit.

## Root Cause (Simplified)

The delay is caused by **QML directory import compilation** — when QML files are compiled at startup, all files in each imported module directory are processed synchronously, blocking the event loop. The Drawers module's import chain cascades to ~61+ files that compile atomically.

Additionally, `Quickshell.Services.Notifications` (a C++ module) blocks ~19s during D-Bus notification daemon registration.

## Key Finding: Quickshell Limitation

**`qs.modules.*` import paths do NOT resolve in URL-loaded files.** This means `Loader.setSource()` and `LazyLoader { source: ... }` cannot be used to defer compilation of files that import `qs.modules.bar`, `qs.modules.agentbar`, etc. Only relative path imports (`import "../../bar"`) work, but `Variants` forces synchronous compilation regardless.

## Recommended Next Step

The user suspects the delay is a regression — it wasn't this slow before the agent dashboard implementation. A **git bisect** approach should identify the commit that introduced or worsened the delay. See `01-profiling-methodology.md` for the heartbeat profiler technique.

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
