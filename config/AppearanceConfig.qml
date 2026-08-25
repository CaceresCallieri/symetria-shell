import Quickshell.Io

JsonObject {
    property Rounding rounding: Rounding {}
    property Spacing spacing: Spacing {}
    property Padding padding: Padding {}
    property FontStuff font: FontStuff {}
    property Anim anim: Anim {}
    property Transparency transparency: Transparency {}
    // NOTE: the former `pillStyle` key lived here and selected "glass"/"matte".
    // It was superseded by the Theme singleton (services/Theme.qml), which
    // selects the whole surface design language, not just pill colours. It was
    // REMOVED rather than kept as an alias: a config key that silently does
    // nothing is worse than an absent one. Theme.material is runtime-only for
    // now — see the persistence note in services/Theme.qml.

    component Rounding: JsonObject {
        property real scale: 1
        property int small: 12 * scale
        property int normal: 17 * scale
        property int large: 25 * scale
        property int full: 1000 * scale
    }

    component Spacing: JsonObject {
        property real scale: 1
        property int small: 7 * scale
        property int smaller: 10 * scale
        property int normal: 12 * scale
        property int larger: 15 * scale
        property int large: 20 * scale
    }

    component Padding: JsonObject {
        property real scale: 1
        property int small: 5 * scale
        property int smaller: 7 * scale
        property int normal: 10 * scale
        property int larger: 12 * scale
        property int large: 15 * scale
    }

    // Every default here must name a font that is actually installed. These are
    // what a fresh clone gets before shell.json exists, and fontconfig silently
    // substitutes a miss rather than erroring — "Rubik" used to sit in `sans`
    // and `clock` and had been resolving to Nimbus Sans on this machine for who
    // knows how long. Verify with `fc-match -f '%{family[0]}\n' <family>`: if it
    // echoes back a different family, the font is not installed.
    component FontFamily: JsonObject {
        property string sans: "JetBrainsMono Nerd Font Propo"
        // Monospaced on purpose: the bar's readouts are live numerals (bar
        // clock, CPU%, RAM, update count) and a proportional face makes them
        // jitter in width as digits change. The previous shell.json override
        // used JetBrainsMono NF *Propo*, the proportional variant. Verify with
        // `fc-match -f '%{family[0]} spacing=%{spacing}\n' <family>` — a
        // monospaced face prints `spacing=100`, a proportional one prints
        // `spacing=` (empty), which is easy to misread as a failed query.
        property string mono: "IBM Plex Mono"
        // Sharp, not Rounded: the shipped material is `metal` (services/Theme.qml)
        // and rounded glyph terminals read soft against a machined surface.
        // Sharp exposes the same [FILL,GRAD,opsz,wght] axes, so MaterialIcon's
        // font.variableAxes block needs no change.
        property string material: "Material Symbols Sharp"
        // The DESKTOP clock only (modules/background/DesktopClock.qml and the
        // dashboard's DateTime) — the bar clock uses `mono`.
        property string clock: "JetBrainsMono Nerd Font Propo"
        // Nerd Font private-use glyphs (distro and package-manager marks) have
        // no Material Symbols equivalent, so they need a face that carries the
        // PUA ranges. Kept separate from `mono` precisely so `mono` is free to
        // be a plain text font: IBM Plex Mono has no PUA coverage, and a glyph
        // rendered without it degrades to tofu rather than to a visible error.
        property string nerd: "Symbols Nerd Font"
    }

    component FontSize: JsonObject {
        property real scale: 1
        property int small: 11 * scale
        property int smaller: 12 * scale
        property int normal: 13 * scale
        property int larger: 15 * scale
        property int large: 18 * scale
        property int extraLarge: 28 * scale
    }

    component FontStuff: JsonObject {
        property FontFamily family: FontFamily {}
        property FontSize size: FontSize {}
    }

    component AnimCurves: JsonObject {
        property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
        property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
        property list<real> expressiveEffects: [0.34, 0.8, 0.34, 1, 1, 1]
    }

    component AnimDurations: JsonObject {
        property real scale: 1
        property int small: 200 * scale
        property int normal: 400 * scale
        property int large: 600 * scale
        property int extraLarge: 1000 * scale
        property int expressiveFastSpatial: 350 * scale
        property int expressiveDefaultSpatial: 500 * scale
        property int expressiveEffects: 200 * scale
    }

    component Anim: JsonObject {
        property AnimCurves curves: AnimCurves {}
        property AnimDurations durations: AnimDurations {}
    }

    component Transparency: JsonObject {
        property bool enabled: false
        property real base: 0.85
        property real layers: 0.4
    }
}
