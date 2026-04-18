---
name: Satellite Architecture Learnings
description: Hard-won lessons from extracting askpass as the first satellite module — blur stacking, Config timing, stdout inheritance, compositor rules
type: project
---

## Satellite Pattern — Proven Architecture

The modular satellite architecture works: each module is its own Quickshell config (`qs -c symmetria-<module>`) that shares code via symlinks to `core/`. Askpass was the first successful extraction.

**Why:** Motivated by Qt 6.11.0 startup regression (80-93s freeze from monolithic Panels.qml loading ~160 files). Satellite modules load on demand in <1s each.

**How to apply:** When extracting the next module, follow the same pattern: create `<module>/shell.qml`, symlink `core/` dirs, register as `~/.config/quickshell/symmetria-<module>`.

## Critical Bugs Encountered

### 1. stdout Inheritance (FIFO corruption)
When launching `qs -c symmetria-askpass &` from a shell script, the satellite inherits the script's stdout — which is piped to sudo. Any Quickshell debug output goes directly to sudo as "password" text. **Fix:** Always redirect: `qs -c symmetria-<module> >/dev/null 2>&1 &`

### 2. Compositor Blur Stacking (visual mismatch)
A satellite surface on any layer ABOVE the Drawers gets its blur applied to the Drawers' already-blurred output — producing double-blur (darker appearance). **Fix:** Add `xray 1` layerrule in Hyprland for satellite namespaces. This blurs the wallpaper directly, skipping intermediate surfaces. Trade-off: also skips client windows ("Phantom Glass" effect — documented in `docs/xray-transparency-effect.md`). The ideal future fix is IPC-based background rendering where the shell's Drawers renders the satellite's background in its own Shape layer.

### 3. Config Async Loading Race
Config uses `FileView` to load `~/.config/symmetria/shell.json` asynchronously. At `Component.onCompleted` time, all Config values are QML DEFAULTS (e.g., `transparency.enabled = false`). Values update ~100-500ms later when FileView finishes. **Fix:** Defer window creation with `Timer { interval: 100 }` before setting `Variants.model`. Bindings update reactively once Config loads.

### 4. FocusManager Construction Order
`FocusManager { active: true }` fires `onActiveChanged` during construction, before sibling items exist — `target` is null. **Fix:** Use a `contentReady` flag set in `Component.onCompleted`, then bind `active: root.contentReady`.

### 5. PAM Faillock Lockout
Failed askpass attempts (from bug #1) trigger PAM's default 3-attempt lockout. **Fix:** `faillock --user jc --reset` to clear. Always check faillock after testing askpass failures.

## Hyprland Layer Rules for Satellites

Every satellite surface needs these rules (already set via `symmetria-.*` glob):
```conf
layerrule = blur on, match:namespace symmetria-.*
layerrule = blur_popups on, match:namespace symmetria-.*
layerrule = ignore_alpha 0.1, match:namespace symmetria-.*
```

Plus xray for satellites that overlap with Drawers:
```conf
layerrule = xray 1, match:namespace symmetria-(...|<new-module>)
```

## Dual-Mode Pattern (Embedded + Standalone)

Satellites detect the shell via IPC: `qs ipc --any-display -c symmetria call agentbar status`. Exit code 0 = shell running = embedded mode. Non-zero = standalone mode.

- **Embedded:** positioned below bar using `Config.bar.sizes.innerWidth` + `Config.border.thickness`, uses TopHangingBackground shape, slide-down animation
- **Standalone:** centered overlay with scrim, self-contained background

## Open Issue: Color Match

The satellite's embedded background doesn't perfectly match the Drawers' native panels due to blur stacking (even with xray, which produces the Phantom Glass effect). True pixel-perfect match requires IPC-based background rendering where the shell renders the satellite's background in the Drawers' Shape layer. This is planned for a future phase.
