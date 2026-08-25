---
name: hand-drawn-svg
description: Create hand-drawn SVG icons matching the Claude sparkle aesthetic. Use when the user asks to create SVG icons, design hand-drawn icons, or needs new icon assets for the Symmetria shell agentbar or similar organic-style UI. Invoke with /hand-drawn-svg.
allowed-tools: "Read,Write,Edit,Glob,Grep,Bash(ls:*)"
---

# Hand-Drawn SVG Icon Creator

Create SVG icons that match the organic, hand-drawn aesthetic of the Claude sparkle sprite sheets used in the Symmetria shell agentbar.

## Style Reference

Read the sparkle sprite SVG to calibrate your aesthetic sense before drawing:

```
{baseDir}/references/style-guide.md
```

Read it with the Read tool before creating any icon.

## Technical Constraints

| Property | Value |
|----------|-------|
| ViewBox | `0 0 100 100` (single icon) |
| Fill | `black` (recolored at runtime via `Colouriser` shader) |
| Fill Rule | `evenodd` when the icon has cutout holes |
| Format | Single `<path>` element, no `<circle>`, `<rect>`, or `<ellipse>` |
| Strokes | **Never.** All shapes are filled paths, not stroked outlines |
| Coordinates | One decimal place, non-round numbers (e.g., `43.6` not `44`) |

## Drawing Rules

### 1. All Edges Are Bezier Curves

Every edge — even "straight" lines — must use cubic bezier curves (`C` command) with subtle deviation from perfectly straight. This prevents the mechanical look of `L` (line-to) commands.

**Exception:** Very short connecting segments (< 5 viewBox units) may use `L` where the difference is invisible at render size.

### 2. Intentional Asymmetry

No shape should be perfectly symmetric. Introduce subtle left-right and top-bottom asymmetry:

- Circles/rings: slightly wider on one side (~1-2 units offset)
- Vertical elements: slight taper or lean
- Horizontal elements: slight slope
- Center points: offset from true mathematical center by 0.3-0.8 units

### 3. Non-Round Coordinates

Use coordinates with one decimal place that avoid round numbers:

| Avoid | Use Instead |
|-------|-------------|
| `50, 30` | `50.3, 29.8` |
| `40, 60` | `40.2, 59.7` |
| `75, 80` | `74.8, 80.3` |

This creates the organic irregularity of hand-drawn paths.

### 4. Visual Weight

Icons render at ~18px (determined by `Appearance.font.size.small * 1.4`). At this size:

- **Wall thickness** of filled regions should be 8-12 viewBox units for normal weight
- **Minimum feature size** is ~8 viewBox units (smaller details vanish at 18px)
- **Cutout holes** need minimum ~20 viewBox units diameter to be visible
- Prefer **lighter/refined weight** over heavy/bold — aim for the lower end of the wall thickness range

### 5. Organic Curves for Circular Shapes

Never use arc commands (`A`). Approximate circles with 4 cubic bezier curves, each with slightly different control point distances:

```
M left_point
C cp1, cp2, top_point
C cp3, cp4, right_point
C cp5, cp6, bottom_point
C cp7, cp8, left_point
Z
```

Vary control point distances from the ideal (radius × 0.5523) by ±0.3-0.8 to create natural wobble.

### 6. Consistent Path Direction

- **Outer boundary:** Clockwise (start bottom-left, go up and around)
- **Inner cutouts:** Counter-clockwise (for `evenodd` fill rule)
- Multiple subpaths in one `d` attribute, each closed with `Z`

## Process

1. **Read the style guide** at `{baseDir}/references/style-guide.md`
2. **Understand the icon concept** — what shape, what it communicates
3. **Sketch the geometry** — plan key points and proportions in the 100×100 viewBox
4. **Draw the outer boundary** first using cubic bezier curves
5. **Draw any cutout holes** as separate subpaths
6. **Review for mechanical regularity** — any perfectly straight lines? Symmetric curves? Round coordinates? Fix them.
7. **Check visual weight** — wall thicknesses in the 8-12 unit range for refined look
8. **Write the SVG** to the target path

## Output Format

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path fill="black" fill-rule="evenodd" d="
    M [start]
    C [outer boundary curves...]
    Z
    M [inner cutout start]
    C [cutout curves...]
    Z
  "/>
</svg>
```

## Example: Key Icon

A permission/authorization key icon with circular bow (ring), shaft, and one tooth:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path fill="black" fill-rule="evenodd" d="
    M 43.6 56.8
    C 41.1 53.4, 28.2 48.1, 24.1 38.2
    C 20.2 28.6, 22.4 19.1, 28.8 12.4
    C 35.2 5.7, 43.4 2.9, 50.8 3.5
    C 58.2 4.1, 66.1 8.8, 71.4 15.9
    C 76.7 23, 78.3 31.8, 75.8 39.3
    C 73.3 46.8, 62.1 53.7, 56.6 56.9
    L 56.4 71.8
    C 56.5 73.1, 57.3 73.7, 58.6 73.9
    L 69.1 74.2
    C 70.5 74.4, 71.3 75.4, 71.2 76.8
    L 71 82.6
    C 70.8 83.9, 69.9 84.6, 68.5 84.5
    L 58.2 84.2
    C 56.9 84.4, 56.2 85.2, 56.1 86.4
    L 56.3 93.4
    C 56.1 94.9, 55 95.9, 53.4 95.8
    L 46.8 95.6
    C 45.2 95.4, 44.1 94.3, 43.7 92.8
    Z
    M 34.6 32.6
    C 35.3 23.4, 41.4 15.8, 50.5 15.2
    C 59.6 14.6, 66.1 21.6, 65.6 31.6
    C 65.1 41.6, 59.2 48.1, 50.3 48.5
    C 41.4 48.9, 33.9 41.8, 34.6 32.6
    Z
  "/>
</svg>
```

**Design notes for this icon:**
- Bow wall thickness: ~10 units (refined weight)
- Shaft width: ~13 units
- Inner hole: ~31 units wide (clearly visible at 18px)
- Tooth protrusion: ~12 units beyond shaft
- Subtle asymmetry: bow wider on right, inner hole slightly off-center

## Integration with Symmetria Shell

Icons created with this skill are used in the agentbar via `Image` + `Colouriser`:

```qml
Image {
    source: Qt.resolvedUrl("../../assets/icon-name.svg")
    sourceSize.width: sparkle._size
    sourceSize.height: sparkle._size
    fillMode: Image.PreserveAspectFit
    layer.enabled: true
    layer.effect: Colouriser {
        sourceColor: "black"
        colorizationColor: "#d97757"  // Claude brand orange
    }
}
```

Place SVG files in `assets/` within the Symmetria project directory.

## Live Preview with Test Pill

**Always** set up a hardcoded test pill in the agentbar after creating a new icon so the user can preview it at real rendered size (~18px, colorized orange) before integrating it into the state machine.

### How to add the test pill

Edit `modules/agentbar/AgentBarContent.qml` — insert a `StyledRect` pill **before** the `Repeater` inside the `RowLayout`:

```qml
// ── HARDCODED TEST PILL — remove after preview ──
StyledRect {
    color: Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, 0.15).background
    radius: Appearance.rounding.full
    border.width: 1
    border.color: Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, 0.15).border
    implicitHeight: Config.agentbar.sizes.innerHeight
    implicitWidth: testPillContent.implicitWidth

    RowLayout {
        id: testPillContent
        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        Item { implicitWidth: Appearance.spacing.smaller; implicitHeight: 1 }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: "test"
            color: Colours.palette.m3primary
            font.weight: Font.Bold
            font.pointSize: Appearance.font.size.small
        }

        // Show the new icon as if it were a static ClaudeSparkle mode.
        // Register the mode in ClaudeSparkle.qml first (see below).
        AgentChip {
            Layout.alignment: Qt.AlignVCenter
            active: true
            activityState: "working"  // or "needs_permission" to trigger key-morph path
            activityTool: ""
            inPlanMode: true  // set true to trigger plan mode path
            isSttTarget: false
        }

        Item { implicitWidth: Appearance.spacing.smaller; implicitHeight: 1 }
    }
}
// ── END HARDCODED TEST PILL ──
```

### How to register a new static icon mode in ClaudeSparkle

In `modules/agentbar/ClaudeSparkle.qml`, add your new mode name to:

1. **`mode` property comment** — add the mode name to the union type
2. **`_frameCount`** — add `root.mode === "yourmode" ? 1` (static icons are 1 frame)
3. **`_spriteAsset`** — map `"yourmode"` → `"your-icon-filename"` (without `.svg`)
4. **`onModeChanged` assert** — add the mode name to the validity check

Then in `AgentChip.qml`, temporarily wire the new mode into `_sparkleMode` for the preview (e.g., replace `"thinking"` with your mode when `inPlanMode` is true).

### After preview

1. **Remove** the hardcoded test pill from `AgentBarContent.qml`
2. **Keep** the ClaudeSparkle mode registration (it's the real integration)
3. **Wire** the mode properly in `AgentChip._sparkleMode` based on actual agent state
4. Clear cache: `rm -rf ~/.cache/quickshell/qmlcache`
