# Claude Sparkle Animation — Research & Implementation Plan

## Overview

Replace the current opacity-pulse animation on agent bar pills (working/thinking state) with the Claude.ai "thinking" sparkle animation — a hand-drawn stop-motion sprite sheet of the Claude starburst icon.

## Extracted Assets

### Sprite Sheet SVG

**File:** `assets/claude-sparkle-sprite.svg`
**Source:** Extracted from claude.ai web interface via Chrome DevTools Protocol (March 2026)

| Property | Value |
|----------|-------|
| viewBox | `0 0 100 800` |
| Frames | 8 (each 100×100, stacked vertically) |
| Fill | `currentColor` (inherits from parent) |
| Size | ~18KB |
| License | Client-side asset from claude.ai; used for personal/open-source project with attribution |

### Animation Parameters (from claude.ai)

| Parameter | Value |
|-----------|-------|
| Total duration | 810ms |
| Frames | 8 (was 9 in an earlier version with a face/head frame) |
| Frame rate | ~101ms per frame |
| Technique | CSS `translateY` stepping through sprite sheet |
| Easing | Linear with step transitions |
| Iteration | Infinite loop |
| Direction | Normal (0→7→0→7→...) |

**Keyframe positions (translateY percentages):**
```
Frame 0: translateY(0%)        = 0/8
Frame 1: translateY(-12.5%)    = 1/8
Frame 2: translateY(-25%)      = 2/8
Frame 3: translateY(-37.5%)    = 3/8
Frame 4: translateY(-50%)      = 4/8
Frame 5: translateY(-62.5%)    = 5/8
Frame 6: translateY(-75%)      = 6/8
Frame 7: translateY(-87.5%)    = 7/8
```

### Color Context

Claude brand orange: `#d97757` / `rgb(215, 119, 87)`

For Symmetria's M3 palette, the animation color should match the existing activity color logic:
- Working/thinking: `Colours.palette.m3primary`
- Error/permission: `Colours.palette.m3error`

## Current Agent Bar Architecture

### Files

| File | Purpose |
|------|---------|
| `modules/agentbar/AgentChip.qml` | Per-agent display: instance number + activity icon + STT badge |
| `modules/agentbar/ProjectGroup.qml` | Per-project pill: glassmorphism container, sweep glow, click-to-focus |
| `modules/agentbar/AgentBarContent.qml` | Horizontal layout of all project pills |
| `modules/agentbar/AgentBarWrapper.qml` | Bottom container, expand/collapse animation |
| `services/AgentService.qml` | Singleton: bridge process, state management |
| `config/AgentBarConfig.qml` | Config (innerHeight: 24px) |

### Current Working State Animation

In `AgentChip.qml`:

```qml
// Opacity pulse: 1.0 → 0.35 → 1.0 over 1.4s (700ms each way)
readonly property bool isBusy: activityState === "working" || activityState === "thinking"
opacity: isBusy ? _pulseValue : 1.0

SequentialAnimation on _pulseValue {
    running: root.isBusy
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.35; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
}
```

### Current Icon System

Activity icons use Material Symbols Rounded (font-based):
- thinking → `psychology`
- working → tool-specific icons (`edit`, `terminal`, `search`, etc.)
- needs_permission → `lock`
- starting → `play_arrow`
- idle → no icon (empty string)

### Pill Dimensions

- Inner height: 24px (from `Config.agentbar.sizes.innerHeight`)
- Font size: `Appearance.font.size.small` (~11pt)
- Content spacing: `Appearance.spacing.small` (~7px)
- Padding: `Appearance.spacing.smaller` (~10px) on each side

## QML Implementation Approach

### Sprite Sheet Animation in QML

QML doesn't have CSS `translateY` on a clipped container natively, but there are equivalent approaches:

#### Option A: Image + clip + y-offset animation

```qml
Item {
    id: sparkleContainer
    width: sparkleSize
    height: sparkleSize
    clip: true
    visible: root.isBusy

    Image {
        id: spriteImage
        source: "qrc:/assets/claude-sparkle-sprite.svg"
        sourceSize.width: sparkleSize
        sourceSize.height: sparkleSize * 8  // 8 frames
        width: sparkleSize
        height: sparkleSize * 8
        y: -currentFrame * sparkleSize

        property int currentFrame: 0
    }

    Timer {
        running: root.isBusy
        interval: 101  // 810ms / 8 frames
        repeat: true
        onTriggered: spriteImage.currentFrame = (spriteImage.currentFrame + 1) % 8
    }
}
```

**Pros:** Simple, uses existing SVG directly, Qt handles SVG rasterization
**Cons:** SVG re-rasterization at small sizes may have artifacts; `clip: true` has minor overhead

#### Option B: AnimatedSprite / SpriteSequence

QML has built-in `AnimatedSprite` for sprite sheets, but it expects horizontal strips or grid layouts (not vertical). Would require rotating/reformatting the sprite sheet.

#### Option C: Canvas frame-by-frame

Pre-split the SVG into 8 individual frames, load each as an Image, swap visibility on a timer.

**Pros:** Full control, no clipping
**Cons:** 8 separate SVG files to manage

#### Option D: Split into individual SVG paths in QML

Extract each frame's path data and use `Shape` + `ShapePath` to draw them, swapping `pathData` on a timer.

**Pros:** Native QML rendering, GPU-accelerated, colorable via `fillColor`
**Cons:** Complexity; `Shape` at small sizes has known rendering issues in Quickshell layer-shell (see MEMORY.md)

### Recommended: Option A (Image + clip)

Simplest approach, directly uses the extracted sprite sheet SVG. If SVG rendering at small sizes is problematic, fall back to pre-rasterized PNGs.

### Size Considerations

The sparkle should replace (or complement) the Material icon in the chip. Current icon size is ~11pt (~15px). The sparkle needs to be recognizable at this size.

Options:
1. **Same size as current icons** (~15px) — minimal layout change
2. **Slightly larger** (~18-20px) — more visible but may affect pill height
3. **Replace the whole chip content** when busy — show only sparkle + instance number

### Color Application

The SVG uses `fill: currentColor`. In QML with Image source, we can't directly use `currentColor`. Options:
- Use `ColorOverlay` (from Qt5Compat.GraphicalEffects or ShaderEffect)
- Use `layer.enabled: true` + `layer.effect: ShaderEffect` for colorization
- Pre-colorize the SVG (loses dynamic theming)
- Use Canvas to draw the SVG path data with custom fill color

### Integration Points

The sparkle animation should:
1. **Show when:** `activityState === "working"` or `activityState === "thinking"`
2. **Replace:** The current Material icon (or sit alongside the instance number)
3. **Color:** Match `_activityColor` (m3primary for working, m3error for permission)
4. **Stop when:** Agent returns to idle/active state (icon disappears, number stays)
5. **Coexist with:** STT badge (graphic_eq icon), sweep glow on pill

## Alternative: CLI-Style Unicode Sparkle

If the sprite sheet approach proves too complex at small sizes, a simpler alternative:

Cycle through 6 Unicode sparkle characters at 120ms intervals:
```
· (U+00B7) → ✢ (U+2722) → ✳ (U+2733) → ✶ (U+2736) → ✻ (U+273B) → ✽ (U+273D)
```
Forward then reverse (mirror bounce), ~2s cycle. This is the Claude Code CLI animation.

```qml
StyledText {
    readonly property var _sparkleChars: ["·", "✢", "✳", "✶", "✻", "✽"]
    property int _sparkleFrame: 0
    property bool _sparkleForward: true

    text: _sparkleChars[_sparkleFrame]
    color: root._activityColor

    Timer {
        running: root.isBusy
        interval: 120
        repeat: true
        onTriggered: {
            if (parent._sparkleForward) {
                parent._sparkleFrame++;
                if (parent._sparkleFrame >= 5) parent._sparkleForward = false;
            } else {
                parent._sparkleFrame--;
                if (parent._sparkleFrame <= 0) parent._sparkleForward = true;
            }
        }
    }
}
```

## Open Questions

1. **Size:** What size should the sparkle be? Same as current icons or larger?
2. **Scope:** Replace just the icon, or the entire chip content (number + icon)?
3. **Alongside tool icons:** Should the sparkle replace tool-specific icons entirely when working, or should the tool icon still appear?
4. **Pulse retention:** Keep the opacity pulse alongside the sparkle, or let the sparkle alone convey "busy"?
5. **Thinking vs working:** Same sparkle for both states, or differentiate (e.g., sparkle for thinking, tool icon + pulse for working)?

## Attribution

The sprite sheet SVG is extracted from claude.ai's client-side code. Add a comment in the source:

```qml
// Claude sparkle animation sprite sheet
// Original asset from claude.ai (Anthropic) — used with attribution
// 8-frame hand-drawn starburst, 810ms cycle
```
