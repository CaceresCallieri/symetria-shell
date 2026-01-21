# Blur Effect Research for Symmetria Shell

## Status: ✅ Working (as of 2026-01-11)

Blur effects successfully enabled on Hyprland 0.53.1.

---

## Requirements

Blur for Symmetria shell requires **two** configurations:

### 1. Shell Transparency (`~/.config/symmetria/shell.json`)

```json
"transparency": {
    "enabled": true,
    "base": 0.6,
    "layers": 0.2
}
```

- `enabled`: Must be `true` for blur to show through
- `base`: Base transparency level (0.6 = 60% opaque)
- `layers`: Layer opacity (0.2 = 20% opaque, more transparent = more blur visible)

### 2. Hyprland Layer Rules (`~/.config/hypr/windowrules.conf`)

The shell creates these layer namespaces (from `hyprctl layers`):
- `symmetria-background` - Background layer
- `symmetria-drawers` - Bar, drawers, panels (main UI)
- `symmetria-border-exclusion` - 1x1 pixel exclusion zones

---

## Hyprland Version Differences

### Hyprland 0.52.x Syntax (Current)

```conf
# Symmetria Shell
layerrule = noanim, symmetria-(launcher|osd|notifications|border-exclusion|area-picker)
layerrule = animation fade, symmetria-(drawers|background)
layerrule = order 1, symmetria-border-exclusion
layerrule = order 2, symmetria-bar
layerrule = xray 1, symmetria-(border|launcher|bar|sidebar|navbar|mediadisplay|screencorners)
layerrule = blur, symmetria-.*
layerrule = blur, qs-.*
layerrule = blurpopups, symmetria-.*
layerrule = ignorealpha 0.57, symmetria-.*
```

### Hyprland 0.53.x Syntax (New - requires upgrade)

```conf
# Symmetria Shell
layerrule = no_anim true, match:namespace symmetria-(launcher|osd|notifications|border-exclusion|area-picker)
layerrule = animation fade, match:namespace symmetria-(drawers|background)
layerrule = order 1, match:namespace symmetria-border-exclusion
layerrule = order 2, match:namespace symmetria-bar
layerrule = xray 1, match:namespace symmetria-(border|launcher|bar|sidebar|navbar|mediadisplay|screencorners)
layerrule = blur true, match:namespace symmetria-.*
layerrule = blur true, match:namespace qs-.*
layerrule = ignore_alpha 0.57, match:namespace symmetria-.*
```

**Key differences in 0.53+:**
- Uses `match:namespace` instead of direct namespace
- Boolean values required: `blur true`, `no_anim true`
- `ignorealpha` → `ignore_alpha`
- `noanim` → `no_anim`

---

## Hyprland Blur Settings (`theme.conf`)

Ensure blur is enabled globally:

```conf
decoration {
    blur {
        enabled = yes
        size = 4
        passes = 3
        new_optimizations = on
        ignore_opacity = on
        xray = false
        special = true
        popups = true
        input_methods = true
    }
}
```

---

## Layer Rule Reference

| Rule | Purpose |
|------|---------|
| `blur` | Enables blur effect |
| `blurpopups` | Enables blur for popups |
| `ignorealpha <value>` | Ignores pixels with alpha below value (0-1) |
| `xray <0/1>` | X-ray mode for blur |
| `noanim` | Disables animations |
| `animation <style>` | Sets animation style (fade, slide, etc.) |
| `order <n>` | Layer stacking order |

---

## Troubleshooting

### Commands

```bash
# Check Hyprland version
hyprctl version

# List all layers and their namespaces
hyprctl layers

# Check if blur is enabled
hyprctl getoption decoration:blur:enabled

# Test layer rule live (doesn't persist)
hyprctl keyword layerrule "blur, symmetria-drawers"

# Reload config
hyprctl reload
```

### Common Issues

1. **No blur visible**: Check `transparency.enabled` is `true` in shell.json
2. **Config errors**: Syntax differs between Hyprland versions
3. **Rules not applying**: Use regex `symmetria-.*` to match all layers

---

## References

- [GitHub Discussion #868](https://github.com/caelestia-dots/shell/discussions/868) - Enabling blur
- [GitHub Issue #622](https://github.com/caelestia-dots/shell/issues/622) - Blur configuration
- [Hyprland Wiki - Window Rules](https://wiki.hypr.land/Configuring/Window-Rules/)
- [Hyprland 0.53 Breaking Changes](https://github.com/hyprwm/Hyprland/releases/tag/v0.53.0)

---

## Current System Info

- **Hyprland Version**: 0.53.1 (Jan 2, 2026)
- **Shell Config**: `~/.config/symmetria/shell.json`
- **Hyprland Rules**: `~/.hyprdots/.config/hypr/windowrules.conf`

---

## Working Configuration

### Key Fix: ignore_alpha Threshold

The critical issue was the `ignore_alpha` value. The shell renders with:
- `transparency.layers = 0.2` (20% alpha on colors)
- `opacity: 0.6` at the Item level in Drawers.qml
- **Effective alpha**: `0.2 × 0.6 = 0.12` (12%)

Original config used `ignore_alpha 0.57`, which told Hyprland to skip pixels below 57% alpha - effectively ignoring all shell elements!

**Solution**: Use `ignore_alpha 0.1` to only skip nearly-transparent pixels.

### Working Layer Rules

```conf
# Symmetria Shell - Blur rules
layerrule = blur on, match:namespace symmetria-.*
layerrule = blur on, match:namespace qs-.*
layerrule = blur on, match:namespace quickshell
layerrule = blur_popups on, match:namespace symmetria-.*
layerrule = ignore_alpha 0.1, match:namespace symmetria-.*
```

### Notes on Regex Patterns

- Hyprland 0.53 `match:namespace` works with simple patterns like `symmetria-.*`
- Anchored regexes `^(...)$` may cause issues - simpler patterns are preferred
