pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Kill-confirm dialog content — warning icon, window info, and action buttons.
///
/// Receives window info as properties and emits signals for confirm/dismiss.
/// Keyboard: Enter = confirm, Escape = dismiss.
StyledRect {
    id: root

    property string windowTitle: ""
    property string windowClass: ""

    signal confirmRequested()
    signal dismissRequested()

    implicitWidth: dialogContent.implicitWidth + Appearance.padding.large * 2
    implicitHeight: dialogContent.implicitHeight + Appearance.padding.large * 2

    readonly property var glassStyle: Colours.pillStyle(
        Colours.palette.m3surfaceContainerHigh,
        Colours.glass.subtle
    )

    radius: Appearance.rounding.normal
    color: glassStyle.background
    border.width: 1
    border.color: glassStyle.border

    focus: true

    Keys.onReturnPressed: event => {
        event.accepted = true;
        root.confirmRequested();
    }

    Keys.onEnterPressed: event => {
        event.accepted = true;
        root.confirmRequested();
    }

    Keys.onEscapePressed: event => {
        event.accepted = true;
        root.dismissRequested();
    }

    ColumnLayout {
        id: dialogContent

        anchors.centerIn: parent
        spacing: Appearance.spacing.normal

        // Warning icon
        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: "warning"
            font.pointSize: Appearance.font.size.larger * 1.5
            color: Colours.palette.m3error
        }

        // Title
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Force kill window?")
            font.pointSize: Appearance.font.size.normal
            font.weight: Font.DemiBold
            color: Colours.palette.m3onSurface
        }

        // Window info
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Appearance.spacing.smaller

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 400
                text: root.windowTitle || qsTr("Unknown window")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                visible: root.windowClass !== ""
                Layout.alignment: Qt.AlignHCenter
                text: root.windowClass
                font.pointSize: Appearance.font.size.smaller
                color: Colours.palette.m3outline
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Warning description
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 350
            text: qsTr("This forcibly kills the process (SIGKILL) with no cleanup. Unsaved work will be lost.")
            font.pointSize: Appearance.font.size.smaller
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        // Action buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Appearance.spacing.normal

            PillButton {
                icon: "close"
                text: qsTr("Cancel")
                onClicked: root.dismissRequested()
            }

            PillButton {
                icon: "delete_forever"
                text: qsTr("Kill")
                pillColor: Colours.palette.m3error
                iconColor: Colours.palette.m3error
                onClicked: root.confirmRequested()
            }
        }

        // Keyboard hint
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Enter to confirm \u00b7 Escape to cancel")
            font.pointSize: Appearance.font.size.smaller
            color: Colours.palette.m3outline
        }
    }
}
