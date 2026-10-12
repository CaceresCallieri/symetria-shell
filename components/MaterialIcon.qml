import qs.services
import qs.config

// The shell's one icon component. `text` is a Material Symbols NAME
// ("volume_up"); the name is the shell's icon vocabulary everywhere — helpers,
// models, shell.json — whichever font draws it.
//
// Theme.glyphs picks that font. Under "phosphor", a name the Phosphor fonts
// cover draws in them (services/Glyphs.qml); any other name, and every name
// under "material", draws in Material Symbols. Never set `font.family` on an
// icon to choose a family: read `iconFamily` if you must restore it, as
// FilledSlider does after showing a number.
//
// Two ways to ask for a filled glyph, and they mean different things:
//   fill  — STATE: 1 for a selected tab, a connected device, a checked toggle.
//           Every family draws it (Phosphor switches to its Fill weight).
//   solid — STYLE: Material's solid look on an icon that is always filled.
//           Only Material draws it; Phosphor stays a hairline, because its
//           Fill weight is a heavy solid shape (a filled caret is a triangle).
StyledText {
    property real fill
    property bool solid: false
    property int grade: Colours.light ? 0 : -25

    readonly property bool drawsPhosphor: Glyphs.covers(text)
    readonly property string iconFamily: drawsPhosphor ? Glyphs.familyFor(fill) : Appearance.font.family.material

    font.family: iconFamily
    font.pointSize: Appearance.font.size.larger
    // Phosphor fonts are static; the axes drive Material Symbols only. Under
    // Phosphor, a Material fallback is drawn thin to sit with the hairlines.
    font.variableAxes: drawsPhosphor ? ({}) : ({
            FILL: Math.max(fill, solid ? 1 : 0).toFixed(1),
            GRAD: grade,
            opsz: fontInfo.pixelSize,
            wght: Theme.glyphs === "phosphor" ? 300 : fontInfo.weight
        })
}
