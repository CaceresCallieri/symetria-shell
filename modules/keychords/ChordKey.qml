pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Visual key chip for the chord overlay.
///
/// Displays a dark key badge (letter) followed by a text label.
/// Clicking or pressing the key triggers the associated chord command.
Item {
    id: root

    required property string keyLetter
    required property string label

    signal activated

    implicitWidth: row.implicitWidth + Appearance.padding.normal * 2
    implicitHeight: Math.max(Config.keychords.sizes.itemHeight, Config.keychords.sizes.keyWidth + Appearance.padding.small * 2)

    StateLayer {
        radius: Appearance.rounding.small

        function onClicked(): void {
            root.activated();
        }
    }

    RowLayout {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Appearance.padding.normal
        spacing: Appearance.spacing.smaller

        // Key letter badge — matches keycaster non-active key style
        StyledRect {
            id: keyBadge

            readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

            Layout.preferredWidth: Config.keychords.sizes.keyWidth
            Layout.preferredHeight: Config.keychords.sizes.keyWidth

            radius: 8
            color: Qt.darker(glassStyle.background, 1.15)
            border.color: glassStyle.border
            border.width: 1

            StyledText {
                anchors.centerIn: parent

                text: root.keyLetter.toUpperCase()
                font.pointSize: Appearance.font.size.small
                font.family: Appearance.font.family.mono
                font.weight: Font.Normal
                color: Colours.palette.m3onSurface
            }
        }

        // Label text
        StyledText {
            Layout.fillWidth: true

            text: root.label
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3onSurface
            elide: Text.ElideRight
        }
    }
}
