pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Individual history entry in the calculator drawer.
///
/// Shows expression = result, with hover state for delete button.
/// Click to reload expression into input field.
Item {
    id: root

    required property var entry
    required property int itemIndex  // Renamed to avoid conflict with ListView's index
    required property PersistentProperties visibilities

    signal deleteRequested(int index)
    signal loadRequested(int index)

    implicitWidth: Config.calculator.sizes.width
    implicitHeight: Config.calculator.sizes.historyItemHeight

    StateLayer {
        radius: Appearance.rounding.normal

        function onClicked(): void {
            root.loadRequested(root.itemIndex);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.padding.larger
        anchors.rightMargin: Appearance.padding.normal
        spacing: Appearance.spacing.small

        // Expression
        StyledText {
            text: root.entry.expression
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.normal
            elide: Text.ElideRight

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        // Equals sign
        StyledText {
            text: "="
            color: Colours.palette.m3outline
            font.pointSize: Appearance.font.size.normal

            Layout.alignment: Qt.AlignVCenter
        }

        // Result
        StyledText {
            text: root.entry.result
            color: Colours.palette.m3primary
            font.pointSize: Appearance.font.size.normal
            font.weight: Font.Medium
            elide: Text.ElideLeft

            Layout.preferredWidth: implicitWidth
            Layout.maximumWidth: parent.width * 0.4
            Layout.alignment: Qt.AlignVCenter
        }

        // Delete button (shows on hover)
        MaterialIcon {
            id: deleteIcon

            text: "close"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.normal

            opacity: deleteArea.containsMouse ? 1 : (stateLayer.containsMouse ? 0.5 : 0)

            Layout.alignment: Qt.AlignVCenter

            MouseArea {
                id: deleteArea

                anchors.fill: parent
                anchors.margins: -Appearance.padding.small
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: root.deleteRequested(root.itemIndex)
            }

            Behavior on opacity {
                Anim {
                    duration: Appearance.anim.durations.small
                }
            }
        }
    }

    // Reference to parent StateLayer for hover detection
    property StateLayer stateLayer: children[0] as StateLayer
}
