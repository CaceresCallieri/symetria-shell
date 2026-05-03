# Glassmorphism Research (2026-04-21)

Reference notes from a prototype attempt to port the Axenide/Ambxst "Liquid Glass" aesthetic to Symmetria. The prototype was **reverted** because the visual result didn't match Ambxst's reference. This doc preserves the findings so a future attempt doesn't have to re-investigate.

Future direction the user expressed interest in: **neumorphism** or **claymorphism** — a matte, tactile, 3D "pressed pill" look — rather than glassmorphism. See final section.

## Source project

- Repo: https://github.com/Axenide/Ambxst
- Project: QuickShell/QML shell (same framework as Symmetria), Axenide's successor to Ax-Shell (which was Fabric/GTK)
- Preset studied: `assets/presets/Liquid Glass/theme.json` + `compositor.json`

## Ambxst's actual "Liquid Glass" recipe (3 layers only)

Despite sophisticated shader infrastructure in the repo (`UnifiedPanelEffect.qml`, `unified_pass1.frag`, `unified_pass2.frag`), **none of it is used in the Liquid Glass preset**. The visible pill look comes from three simple layers:

### 1. Hyprland compositor blur (the frost)

```
decoration {
    blur {
        enabled = yes
        size = 4
        passes = 2
        ignore_opacity = on
        special = true
    }
}
layerrule = match:namespace ^(ambxst)$, blur on
```

### 2. `StyledRect` with radial-gradient shader (the tint)

From `Liquid Glass/theme.json`:
```json
"srBg": {
    "gradient": [["background", 0.25], ["overBackground", 0.75]],
    "gradientType": "radial",
    "gradientCenterX": 0.401, "gradientCenterY": 0.399,
    "border": ["surfaceVariant", 0],      // zero border width
    "opacity": 0.3
}
```

Radial gradient at opacity 0.3, off-center at (0.4, 0.4), using theme palette keys (NOT hardcoded colors). The `border[1] = 0` means no stroke is drawn — this is important.

### 3. `Qt6 MultiEffect` drop shadow (the halo)

From `Shadow.qml`:
```qml
MultiEffect {
    shadowEnabled: true
    shadowBlur: 1.0           // Qt's normalized max (0..1 scale)
    shadowOpacity: 0.5
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
    shadowColor: Config.resolveColor("shadow")
}
```

Applied via `layer.effect: Shadow {}` on `StyledRect`. MultiEffect naturally bleeds outside the item's geometry — **no parent-sizing/padding tricks needed**.

### Bar layer is fully transparent

`srBarBg.opacity: 0` in the Liquid Glass preset. The bar itself is invisible; pills float as individual elements on a transparent bar layer, with wallpaper visible between them.

## Critical dead-code warning

**`UnifiedPanelEffect.qml` is dead code in Ambxst's main branch.** Zero QML files instantiate it. The `unified_pass1.frag` + `unified_pass2.frag` shaders (dilation-ring border + alpha-blur shadow) are impressive but unused in the shipping presets. Initial research mistook the file's sophistication for load-bearing — always grep for `UnifiedPanelEffect {` usage before trusting it.

## Our prototype attempts (and why they didn't match)

### Attempt 1: Simple tint
- Dark tint gradient (#4a4a4a → #050505) + 1px white border + Qt MultiEffect shadow
- **Result**: pills blended with backdrop, too subtle

### Attempt 2: Bright contrasting tint
- Bumped opacity to 0.55, white-ish highlight + dark edge
- **Result**: pills visible but "painted" rather than "glass"

### Attempt 3: Port unified_pass1/pass2 shaders
- Full two-pass alpha-blur with dilation ring + shape shadow
- **Result**: pills broke entirely (shader URL resolution issue, then sizing issues, then still didn't match Ambxst's look)

### Attempt 4: Match Ambxst's exact theme.json values
- opacity 0.30, center (0.4, 0.4), MultiEffect shadow blur=1.0 opacity=0.5
- **Result**: faded, low-contrast, did not look like reference — user reverted

### Root cause of mismatch
Unclear. Candidates:
- Our M3 palette colors (resolved from `Colours.palette`) may differ from Ambxst's "background" / "overBackground" derivations
- Our wallpaper happens to be low-contrast (forest/rusty) — Ambxst's reference screenshot was on a different backdrop
- Our bar has a `srBarBg`-equivalent that isn't fully transparent
- Qt version or GPU differences in MultiEffect rendering
- Possibly font sizing / icon spacing making pills visually "less tight"

A future investigation should compare screenshots pixel-by-pixel against Ambxst's reference under the same wallpaper.

## Key gotchas learned

### Hyprland layer rules (0.53+ syntax)
```
layerrule = match:namespace ^(<regex>)$, <rule> <value>
```
- Match-first ordering (not rule-first)
- Boolean rules need `on`/`off` explicit value
- Keyword is `ignore_alpha` with underscore, not `ignorealpha`

### Hyprland blur scope
- Global `decoration.blur.enabled = yes` applies to **windows**, not layer-shell surfaces
- Layer surfaces require explicit `layerrule = blur on, match:namespace ...`
- `ignore_opacity = on` + full-screen transparent layer = blur appears EVERYWHERE
- Use `layerrule = ignore_alpha N` per-namespace to gate blur to non-transparent pixels

### Qt6 ShaderEffect URL resolution
- Relative `vertexShader: "foo.qsb"` strings can fail when the component is a root ShaderEffect instantiated from another file
- Always wrap: `vertexShader: Qt.resolvedUrl("foo.qsb")` to force resolution from declaring file
- `qsb` compiler at `/usr/lib/qt6/bin/qsb`
- Compile command: `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o foo.frag.qsb foo.frag`

### QML shader property gotchas
- `int` uniforms work in std140 blocks but require property type `int` in QML
- Colors passed as `vector4d` must be premultiplied (`r*a, g*a, b*a, a`) for "over" blending
- ShaderEffectSource with `live: false` + `hideSource: true` still captures the source once
- `layer.enabled: true` is REQUIRED for MultiEffect shadow to render (silent failure otherwise)

### QuickShell specifics
- `ClippingRectangle` (from `Quickshell.Widgets`) enforces rounded-corner clipping on children (plain Rectangle doesn't)
- `qs.components.effects.glass` import path resolves via directory structure automatically
- Layer namespace = `symmetria-<name>` via `StyledWindow` component

## Exact file references in Ambxst's tree

For a future port, these are the files to read (under `raw.githubusercontent.com/Axenide/Ambxst/main/`):

**The actual "glass" (simple):**
- `modules/components/StyledRect.qml` — the base tinted container
- `modules/components/Shadow.qml` — the MultiEffect wrapper
- `modules/components/ToggleButton.qml` — the pill base
- `modules/shell/UnifiedShellPanel.qml` — the layer hierarchy
- `modules/shell/bar/BarBg.qml` — the bar container
- `assets/presets/Liquid Glass/theme.json` — exact color/opacity numbers
- `assets/presets/Liquid Glass/compositor.json` — Hyprland blur settings

**The "heavy" shader (unused by Liquid Glass, but exists):**
- `modules/components/UnifiedPanelEffect.qml` — wrapper
- `modules/components/unified_pass1.frag` — horizontal alpha blur
- `modules/components/unified_pass2.frag` — vertical blur + dilation + composition
- `modules/components/unified_pass1.vert` / `unified_pass2.vert` — passthrough vertex shaders
- These are dead code in the Liquid Glass preset but could be interesting for alternative presets

## Future: neumorphism / claymorphism direction

The user expressed interest in a different aesthetic than glassmorphism — a "matte pill with 3D effect". The likely terms:

### Neumorphism (soft UI)
- Matte (no transparency/blur)
- Two shadows: light (top-left) + dark (bottom-right), both soft, often equal blur
- Produces "pressed into surface" or "extruded from surface" feel
- Works best with low-contrast backgrounds and minimal color palettes
- QML implementation: two MultiEffect passes (one for each shadow direction) or two Rectangle overlays with opposite offsets
- Risk: low contrast can hurt accessibility; requires tight color control

### Claymorphism
- Plastic-toy 3D look — softer, more saturated than neumorphism
- Often uses vivid colors, rounded shapes, puffy highlights
- Combination of outer shadow + inner highlight + solid fill
- Good for playful / approachable UI

### Possible Symmetria approach
- Pills as matte rounded rects with M3 surface color fill
- Inner highlight on top (subtle bright stripe/gradient)
- Inner shadow on bottom (subtle dark gradient)
- Outer soft shadow for lift
- Optional: subtle glossy gradient if drifting toward claymorphism

A prototype along these lines would likely succeed where glassmorphism didn't, because it's less dependent on complex compositor + shader interactions and instead just needs well-chosen shadow layers.

## Revert commit

This research doc was added after reverting branch `feature/glassmorphism-prototype`. No code changes remain from that branch.
