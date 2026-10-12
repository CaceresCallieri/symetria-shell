pragma Singleton

import Quickshell
import QtQml

Singleton {
    // Literally just here to shorten accessing stuff :woe:
    // Also kinda so I can keep accessing it with `Appearance.xxx` instead of `Config.appearance.xxx`
    readonly property AppearanceConfig.Rounding rounding: Config.appearance.rounding
    readonly property AppearanceConfig.Spacing spacing: Config.appearance.spacing
    readonly property AppearanceConfig.Padding padding: Config.appearance.padding
    readonly property AppearanceConfig.FontStuff font: Config.appearance.font
    readonly property AppearanceConfig.Anim anim: Config.appearance.anim
    readonly property AppearanceConfig.Transparency transparency: Config.appearance.transparency
    readonly property Emphasis emphasis: Emphasis {}
    // `pillStyle` was forwarded here; it moved to the Theme singleton
    // (services/Theme.qml) — use `Theme.material`.

    // Two tones for content that shares one colour. A glyph or unit that labels
    // a figure recedes to `secondary` so the eye lands on the figure; a status
    // glyph that stands alone sits at `status`. Applied as an alpha on the
    // content colour. Design constants, not settings: deliberately outside
    // AppearanceConfig, so shell.json neither carries nor overrides them.
    component Emphasis: QtObject {
        readonly property real secondary: 0.55
        readonly property real status: 0.85
    }
}
