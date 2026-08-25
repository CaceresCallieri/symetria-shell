pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick

/// Search bar for the packages drawer.
/// Contains: search text field, submit button, clear icon.
/// Exposes focusTarget for FocusManager in Content.qml.
StyledRect {
    id: root

    required property int padding

    /// Current raw search text (alias to internal text field).
    property alias text: search.text

    /// Focus target for FocusManager (the text field itself).
    readonly property alias focusTarget: search

    signal accepted
    signal navigateUp
    signal navigateDown
    signal searchRequested
    signal searchTextEdited(string text)

    // ── Layout ────────────────────────────────────────────────────

    color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
    radius: Appearance.rounding.full

    implicitHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight, submitButton.implicitHeight, clearIcon.implicitHeight)

    MaterialIcon {
        id: searchIcon

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.padding

        text: "search"
        color: Colours.palette.m3onSurfaceVariant
    }

    StyledTextField {
        id: search

        anchors.left: searchIcon.right
        anchors.right: submitButton.left
        anchors.leftMargin: Appearance.spacing.small
        anchors.rightMargin: Appearance.spacing.small

        topPadding: Appearance.padding.larger
        bottomPadding: Appearance.padding.larger

        placeholderText: qsTr("Search packages...")

        onTextChanged: root.searchTextEdited(text)
        onAccepted: root.accepted()

        Keys.onUpPressed: root.navigateUp()
        Keys.onDownPressed: root.navigateDown()
    }

    // Search submit button (circular arrow)
    StyledRect {
        id: submitButton

        readonly property bool canSearch: search.text.trim().length >= 2 && search.text.trim() !== Packages.currentQuery

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: clearIcon.left
        anchors.rightMargin: Appearance.spacing.small

        implicitWidth: submitIcon.implicitWidth + Appearance.padding.normal * 2
        implicitHeight: implicitWidth
        radius: Appearance.rounding.full
        color: canSearch ? Colours.palette.m3primary : "transparent"

        MaterialIcon {
            id: submitIcon
            anchors.centerIn: parent
            text: "arrow_forward"
            font.pointSize: Appearance.font.size.normal
            color: submitButton.canSearch ? Colours.palette.m3onPrimary : Colours.palette.m3outline
        }

        StateLayer {
            visible: submitButton.canSearch
            radius: parent.radius
            color: Colours.palette.m3onPrimary

            function onClicked(): void {
                root.searchRequested();
            }
        }

        Behavior on color {
            CAnim {}
        }
    }

    MaterialIcon {
        id: clearIcon

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.padding

        width: search.text ? implicitWidth : implicitWidth / 2
        opacity: {
            if (!search.text)
                return 0;
            if (mouse.pressed)
                return 0.7;
            if (mouse.containsMouse)
                return 0.8;
            return 1;
        }

        text: "close"
        color: Colours.palette.m3onSurfaceVariant

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: search.text ? Qt.PointingHandCursor : undefined

            onClicked: {
                search.text = "";
                search.forceActiveFocus();
            }
        }

        Behavior on width {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }
    }
}
