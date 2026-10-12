pragma ComponentBehavior: Bound

import qs.services
import qs.utils
import qs.config
import QtQuick

// One glyph in the bar. `icon` is a Material Symbols name; utils/BarGlyphs.qml
// translates it to Phosphor Light and explains why the bar keeps the Material
// vocabulary.
//
// Colour goes through `tint` and `tintAlpha`, never `color` or `opacity`.
// Callers animate `opacity` to show and hide a glyph (the lock keys, a pairing
// Bluetooth device), so a dim tone written as opacity would fight those
// animations. The alpha rides on the colour instead.
StyledText {
    id: root

    required property string icon
    property color tint: Colours.palette.m3onSurface
    property real tintAlpha: 1
    // Read by the Material fallback only: Phosphor Light has one fill.
    property real fill: 0

    readonly property int codepoint: BarGlyphs.family !== "" ? BarGlyphs.codepointFor(icon) : 0
    readonly property bool drawsPhosphor: codepoint > 0

    text: drawsPhosphor ? String.fromCodePoint(codepoint) : icon
    color: Qt.alpha(tint, tintAlpha)
    font.family: drawsPhosphor ? BarGlyphs.family : Appearance.font.family.material
    font.pointSize: Appearance.font.size.larger
    // The fallback matches Phosphor Light's stroke: thin and outlined. Its grade
    // follows the theme the way MaterialIcon's does.
    font.variableAxes: drawsPhosphor ? ({}) : ({
            FILL: fill.toFixed(1),
            GRAD: Colours.light ? 0 : -25,
            opsz: fontInfo.pixelSize,
            wght: 300
        })
}
