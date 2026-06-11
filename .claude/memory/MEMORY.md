# Symmetria Shell - Working Memory

## QML Pitfalls Reference
All QML gotchas (property shadowing, type collisions, transparency compensation, XOR mask, cursor shadowing, small-size rendering) are now in `docs/qml-pitfalls.md`. Always clear `~/.cache/quickshell/qmlcache/` after QML edits.

### MonthGrid Async Delegate Creation (KNOWN BUG — LOW PRIORITY)
Qt Quick Controls `MonthGrid` creates its 42 delegates asynchronously across multiple frames. The bar's calendar popout (reusing `Dash.Calendar`) shows compressed rows ~20-30% of the time because `implicitHeight` is read before all delegates exist. The `anchors.fill` circular dependency was fixed (changed to `anchors.left/right/top` in `Dash.Calendar`), which reduced frequency but didn't eliminate the async issue. 6 approaches tried — none fully solved it. Most promising untried: keep Calendar alive across popout cycles (approach D in the knowledge file).

**Full debug log + all approaches tried:** [calendar-popout-sizing-bug.md](calendar-popout-sizing-bug.md)

## Build & Deploy

**QML/SVG-only changes** (no C++ touched):
```bash
rm -rf ~/.cache/quickshell/qmlcache && symmetria shell -d
```

**C++ plugin changes** (files in `plugin/src/`):
```bash
cmake --build build && sudo cmake --install build && sudo chown -R $USER:$USER ~/.config/quickshell/symmetria
rm -rf ~/.cache/quickshell/qmlcache
```

## Claude.ai Sparkle Sprites
Two hand-drawn SVG sprite sheets extracted from claude.ai for the agentbar:
- **Working** (8 frames, `0 0 100 800`): starburst rotation during streaming
- **Thinking** (9 frames, `0 0 100 900`): dot→starburst→dot breathing cycle

Sprites are ephemeral DOM elements — must be captured via CDP polling during active thinking/streaming. Path data is NOT in JS bundles.

**Full extraction guide:** [claude-ai-sprite-extraction.md](claude-ai-sprite-extraction.md)

## Agent Bridge Fixes — READY TO COMMIT
After code review, the startup delay was identified as a **system-wide issue**, not project-level.
Deferred Panels loading was **reverted** (over-engineering). Kept changes (4 files):
- Bridge emit coalescing 50ms (`agent-bridge.py`) — reduces reconnect burst spam
- SIGTERM-only stale bridges (`agent-bridge.py`) — fixes crash loop bug
- QML throttle 100ms + backoff timer fix (`AgentService.qml`) — `.start()` not `.restart()`
- `QT_QPA_PLATFORM=wayland` pragma (`shell.qml`)
- `_shouldGrabFocus` extraction (`Drawers.qml`) — readability improvement

## Startup Delay — FIXED (2026-04-04)
- **ROOT CAUSE:** O(n²) notification deserialization in `services/Notifs.qml`. With 6,890 accumulated notifications, each `push()` triggers `notClosed`/`popups` filter bindings = 47M filter operations.
- **Fix:** Batch-build local array, single assignment: `root.list = loaded`. Result: 23s → 976ms.
- **Why bisection was misleading:** The rebrand commit changed `Paths.state` path, not the plugin. Old path didn't exist → zero notifications loaded → fast.
- **Qt 6.11.0 regression (separate, untested since fix):** Was 80-93s on 6.11.0 vs 23s on 6.10.2. Qt/QS were pinned but should now be unpinned since the root cause was data, not Qt.
- **Postmortem:** `docs/startup-delay-investigation/11-postmortem-and-learnings.md`
- **Full investigation:** `docs/startup-delay-investigation/`

## Architecture: Staying Monolithic (decision 2026-04-06)
**The monolithic architecture is the chosen direction.** No plans to break into satellite processes.
- The `refactor/modular-satellites` branch exists with Phase 1-2 work (askpass + killconfirm extracted as satellites) but is **shelved indefinitely**. Do NOT continue that work or reference it as a future direction.
- The branch is preserved for reference only. Do not merge, rebase, or build upon it.
- Previous plan: `docs/architecture-rewrite-plan.md` — treat as historical, not actionable.
- [satellite-architecture-learnings.md](satellite-architecture-learnings.md) — Some QML learnings may still be useful independent of the architecture decision.

## Feedback
- [feedback_always_clear_cache.md](feedback_always_clear_cache.md) — Always clear QML cache yourself after changes, don't just tell the user
- [feedback_shell_instance_awareness.md](feedback_shell_instance_awareness.md) — Check for running shell before launching test qs instances
- [feedback_kill_all_instances.md](feedback_kill_all_instances.md) — ALWAYS pkill -x quickshell + verify before benchmarks. Multiple instances cause 2-3x contamination.
- [feedback_multiple_measurements.md](feedback_multiple_measurements.md) — Never use single measurements. Run 3+ times, report min/median/max.
- [feedback_subagent_coordination.md](feedback_subagent_coordination.md) — Wait for ALL subagents before compiling reports; don't duplicate their work
- [feedback_regression_documentation.md](feedback_regression_documentation.md) — Document regressions from code review fixes with inline comments + docs

- [project_monolithic_architecture.md](project_monolithic_architecture.md) — Shell stays monolithic, satellite branch shelved
- [project_frozen_dark_theme.md](project_frozen_dark_theme.md) — Scheme system removed, frozen to warm-neutral dark (2026-04-11)
- [project_cli_consolidation_progress.md](project_cli_consolidation_progress.md) — CLI issues #50-#52 done, #53-#55 open
- [project_wifi_no_secret_agent.md](project_wifi_no_secret_agent.md) — Wi-Fi connect fails silently w/o NM secret agent; saved-profile null-callback bug + BSSID-pin removed (2026-06-07)
- [project_lock_crash_observability.md](project_lock_crash_observability.md) — Lock "armed but undrawn" on resume; NOT hyprlock (own WlSessionLock); blank-ScreencopyView hypothesis; observability added, awaiting next crash (2026-06-07)

## References
- [reference_orchestrator_remote_reload.md](reference_orchestrator_remote_reload.md) — Reload orchestrator in all NeoVim instances via RPC sockets

## Key File Locations
- QML cache: `~/.cache/quickshell/qmlcache/`
- Runtime logs: `qs log -c symmetria -n` (binary .qslog format, use `qs log` to read)
- User config: `~/.config/symmetria/shell.json`

## Ecosystem Naming (absorbed from agents-naming)
- [Symmetria Umbrella Decision](project_symmetria_umbrella_decision.md) — Symmetria evolves into conceptual umbrella for the entire personal computing environment
- [Naming Constellation](project_naming_constellation.md) — Map of all named projects and their conceptual positions
- [Naming Philosophy](user_naming_philosophy.md) — How the user approaches naming: preferences, values, collaboration style
