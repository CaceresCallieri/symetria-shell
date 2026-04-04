# Phantom Glass Effect — Hyprland Xray Layer Transparency

**Discovered:** 2026-04-04 during askpass satellite extraction
**Status:** Documented for future use

## What It Is

A single Hyprland layer rule makes a layer-shell surface's blur **see through all intermediate surfaces** (client windows, other shell surfaces) directly to the wallpaper. The result is a "phantom" panel that appears to exist on a separate visual plane — you can see the wallpaper painting through the panel background while client window content remains visible but "behind" the glass.

## The Rule

```conf
layerrule = xray 1, match:namespace <surface-namespace>
```

Combined with the standard blur setup:
```conf
layerrule = blur on, match:namespace <surface-namespace>
layerrule = ignore_alpha 0.1, match:namespace <surface-namespace>
```

## How It Works

Without `xray 1` (normal blur):
```
Panel (blur) → sees Drawers surface → sees blurred wallpaper → double-processed
```

With `xray 1`:
```
Panel (blur) → SKIPS all surfaces → blurs raw wallpaper directly
```

Hyprland's compositor processes blur in layer order. Normally, a surface's blur operates on whatever is composited below it — including already-blurred surfaces. `xray 1` bypasses this chain and samples the wallpaper (background layer) directly for its blur input.

## Visual Effect

- Panel background becomes a frosted-glass window into the wallpaper
- Client windows (terminals, browsers) beneath the panel are visible through the tint but their content is NOT blurred into the panel — the panel ignores them
- Creates an ethereal, layered depth effect where the shell feels like it exists on a separate visual plane from application windows
- Particularly striking with artistic/detailed wallpapers

## Use Cases

1. **Shell overlays** — Panels that should feel "above" the desktop without being affected by what's running beneath them
2. **Lock screen effects** — Blur only the wallpaper, not the last visible application state (security benefit)
3. **Ambient panels** — Dashboard or widget panels that show a consistent frosted wallpaper regardless of open windows
4. **Focus mode** — A panel that visually "detaches" from the workspace below

## Current Usage in Symmetria

Already applied to several shell surfaces:
```conf
layerrule = xray 1, match:namespace symmetria-(border|launcher|bar|sidebar|navbar|mediadisplay|screencorners)
```

The askpass satellite temporarily had it added (`|askpass`) during testing — produces the phantom glass effect on the password dialog.

## Relationship to the Askpass Color Bug

The askpass satellite (a separate Quickshell process) renders on its own layer-shell surface. Without xray, its blur double-processes through the Drawers surface beneath it, producing a darker appearance than Drawers-native panels. With xray, it goes too far (ignoring client windows too). The ideal middle ground requires the satellite's background to be rendered within the Drawers surface itself (planned for future IPC-based approach).
