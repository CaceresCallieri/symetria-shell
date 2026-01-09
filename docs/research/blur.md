# Blur Effect Research for Caelestia Shell

## Status: Not Working (as of 2026-01-09)

Blur effects have not been successfully enabled on Hyprland 0.52.2. Further investigation needed.

---

## Requirements

Blur for Caelestia shell requires **two** configurations:

### 1. Shell Transparency (`~/.config/caelestia/shell.json`)

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
- `caelestia-background` - Background layer
- `caelestia-drawers` - Bar, drawers, panels (main UI)
- `caelestia-border-exclusion` - 1x1 pixel exclusion zones

---

## Hyprland Version Differences

### Hyprland 0.52.x Syntax (Current)

```conf
# Caelestia Shell
layerrule = noanim, caelestia-(launcher|osd|notifications|border-exclusion|area-picker)
layerrule = animation fade, caelestia-(drawers|background)
layerrule = order 1, caelestia-border-exclusion
layerrule = order 2, caelestia-bar
layerrule = xray 1, caelestia-(border|launcher|bar|sidebar|navbar|mediadisplay|screencorners)
layerrule = blur, caelestia-.*
layerrule = blur, qs-.*
layerrule = blurpopups, caelestia-.*
layerrule = ignorealpha 0.57, caelestia-.*
```

### Hyprland 0.53.x Syntax (New - requires upgrade)

```conf
# Caelestia Shell
layerrule = no_anim true, match:namespace caelestia-(launcher|osd|notifications|border-exclusion|area-picker)
layerrule = animation fade, match:namespace caelestia-(drawers|background)
layerrule = order 1, match:namespace caelestia-border-exclusion
layerrule = order 2, match:namespace caelestia-bar
layerrule = xray 1, match:namespace caelestia-(border|launcher|bar|sidebar|navbar|mediadisplay|screencorners)
layerrule = blur true, match:namespace caelestia-.*
layerrule = blur true, match:namespace qs-.*
layerrule = ignore_alpha 0.57, match:namespace caelestia-.*
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
hyprctl keyword layerrule "blur, caelestia-drawers"

# Reload config
hyprctl reload
```

### Common Issues

1. **No blur visible**: Check `transparency.enabled` is `true` in shell.json
2. **Config errors**: Syntax differs between Hyprland versions
3. **Rules not applying**: Use regex `caelestia-.*` to match all layers

---

## References

- [GitHub Discussion #868](https://github.com/caelestia-dots/shell/discussions/868) - Enabling blur
- [GitHub Issue #622](https://github.com/caelestia-dots/shell/issues/622) - Blur configuration
- [Hyprland Wiki - Window Rules](https://wiki.hypr.land/Configuring/Window-Rules/)
- [Hyprland 0.53 Breaking Changes](https://github.com/hyprwm/Hyprland/releases/tag/v0.53.0)

---

## Current System Info

- **Hyprland Version**: 0.52.2 (Dec 3, 2025)
- **Latest Available**: 0.53.1 (Jan 2, 2026)
- **Shell Config**: `~/.config/caelestia/shell.json`
- **Hyprland Rules**: `~/.hyprdots/.config/hypr/windowrules.conf`

---

## Next Steps to Try

1. **Upgrade to Hyprland 0.53.1**: `paru -Syu hyprland`
2. **Update all layer rules** to new 0.53 syntax
3. **Check if QML needs blur passthrough** - May need to investigate Quickshell/QML layer configuration
4. **Test with simpler config** - Try just `layerrule = blur, caelestia-drawers` alone
