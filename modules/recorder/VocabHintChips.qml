pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Vocabulary hint chip row for STT sessions.
///
/// Renders deletable chip pills for each entry in SttService.sessionVocabHints.
/// Hovering a chip reveals a delete icon; clicking removes the hint.
/// Used by the drawer Content card. It was shared with the bar-embed
/// RecordingActions popout, which went out with the merged agent bar.
Row {
    id: root

    spacing: Appearance.spacing.smaller

    // ScriptModel, not a bare array: sessionVocabHints is re-assigned on every
    // add/remove, and a plain JS array model resets ALL delegates (the
    // docs/qml-pitfalls.md Repeater pitfall) — chips hold hover state, so an
    // unrelated chip would visibly flicker when a sibling is deleted.
    Repeater {
        model: ScriptModel {
            values: SttService.sessionVocabHints
        }

        StyledRect {
            id: hintChipBg

            required property string modelData
            required property int index

            implicitWidth: Math.max(chipText.implicitWidth, chipDeleteIcon.implicitWidth) + Appearance.padding.large * 2
            implicitHeight: chipText.implicitHeight + Appearance.padding.small * 2

            radius: Appearance.rounding.full
            color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background

            MouseArea {
                id: chipDeleteArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SttService.removeSessionHint(index)
            }

            StyledText {
                id: chipText

                anchors.centerIn: parent
                visible: !chipDeleteArea.containsMouse
                text: modelData
                color: Colours.palette.m3onSurface
                font.pointSize: Appearance.font.size.small
            }

            MaterialIcon {
                id: chipDeleteIcon

                anchors.centerIn: parent
                visible: chipDeleteArea.containsMouse
                text: "delete"
                color: Colours.palette.m3error
                font.pointSize: Appearance.font.size.small
            }
        }
    }
}
