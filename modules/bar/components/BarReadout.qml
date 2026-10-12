pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

// A number in the bar with optional words around it: "Sun 11 Oct", "12%",
// "17.5G", "13°". The number stays at full strength; the prefix and the unit
// are smaller and recede (Appearance.emphasis.secondary), so the eye lands on the
// figure. The parts are baseline-aligned and the caller writes any spacing
// into them (" Oct" vs "%"), because only the caller knows whether the unit is
// a word or a symbol.
Row {
    id: root

    required property string value
    property string prefix: ""
    property string unit: ""
    property color colour: Colours.palette.m3tertiary

    spacing: 0

    Affix {
        anchors.baseline: valueText.baseline
        text: root.prefix
        base: root.colour
    }

    StyledText {
        id: valueText

        text: root.value
        font.pointSize: Appearance.font.size.smaller
        font.family: Appearance.font.family.mono
        font.weight: Font.Light
        color: root.colour
    }

    Affix {
        anchors.baseline: valueText.baseline
        text: root.unit
        base: root.colour
    }

    // The prefix and the unit share one look. An inline component cannot see
    // this file's ids, so each use site passes the baseline and the colour.
    component Affix: StyledText {
        property color base

        visible: text !== ""
        font.pointSize: Appearance.font.size.smaller * 0.8
        font.family: Appearance.font.family.mono
        font.weight: Font.Light
        color: Qt.alpha(base, Appearance.emphasis.secondary)
    }
}
