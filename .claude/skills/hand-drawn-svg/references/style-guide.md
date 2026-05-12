# Claude Sparkle Aesthetic — Style Guide

## Source Material

The Claude sparkle sprites are hand-drawn SVGs extracted from claude.ai. They define the visual language for all icons in the Symmetria shell agentbar.

**Reference files** (read one before drawing to calibrate your aesthetic):
- Working sprite (8 frames): `~/.config/quickshell/symmetria/assets/claude-sparkle-sprite.svg`
- Stopping sprite (12 frames): `~/.config/quickshell/symmetria/assets/claude-sparkle-stopping-sprite.svg`

## Key Characteristics

### Path Data Style

The sparkle paths use:
- **Many small segments** rather than few large smooth curves
- **Cubic bezier curves** (`c`/`C`) for organic shapes
- **Non-round coordinates** with high decimal precision (e.g., `19.622`, `66.499`)
- **No geometric primitives** — no `<circle>`, `<rect>`, `<ellipse>`, no arc commands (`A`)
- **Filled shapes** (no strokes) — all visual weight comes from fill area

### Visual Character

| Quality | Description |
|---------|-------------|
| Organic | No mathematically perfect shapes — circles wobble, lines flex |
| Warm | Soft transitions, rounded approach to corners |
| Imperfect | Intentional asymmetry — nothing is centered or balanced precisely |
| Bold but refined | Clear silhouette with enough detail to be interesting |
| Confident | Lines don't hesitate — each curve commits to its direction |

### What to Avoid

| Bad | Why | Good Alternative |
|-----|-----|-----------------|
| Perfect circles (`A` arcs) | Looks mechanical, breaks organic feel | 4 bezier curves with varied control points |
| Right angles | Too sharp, feels computer-generated | Soft bezier transitions (2-3 unit radius) |
| Mirror symmetry | Instantly looks artificial | Vary left/right by 0.5-2 units |
| Round coordinates | Grid-snapped feeling | Add .1-.9 decimal offsets |
| Thin strokes | Sparkle uses filled shapes, not lines | Fill regions with 8-12 unit wall thickness |
| Overly complex detail | Vanishes at 18px render size | Bold, simple shapes with subtle character |

### Scale Reference

The sparkle starburst at full size fills approximately 80% of its 100×100 viewBox frame. The dormant dot occupies roughly 8×8 units at center. New icons should use similar coverage — don't make tiny icons floating in empty space, and don't bleed to the edges.

## Color Pipeline

All SVGs are pure black. Color is applied at runtime:
1. SVG loaded as black-filled shape
2. `Colouriser` shader remaps black → target color
3. Primary color: `#d97757` (Claude brand orange)
4. Color may vary by state (orange for active, themed colors for other states)

**Implication:** Design only the silhouette. Never embed color information in the SVG.
