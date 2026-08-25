pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick

/// Vocabulary hint chip row for STT sessions.
///
/// Renders deletable chip pills for each entry in SttService.sessionVocabHints.
/// Hovering a chip reveals a delete icon; clicking removes the hint.
/// Used by both the drawer Content card and the bar-embed RecordingActions popout.
Row {
    id: root

    spacing: Appearance.spacing.smaller

    Repeater {
        model: SttService.sessionVocabHints

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
