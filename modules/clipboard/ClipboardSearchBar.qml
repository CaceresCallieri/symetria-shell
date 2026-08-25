pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick

/// Bottom search bar for the clipboard Text tab.
/// Collapses to zero height on the Images tab with a smooth animation.
/// Owns: search text field, debounce timer, clear/delete-all button state.
/// Loaded inline by Content.qml; exposes focusTarget for FocusManager.
///
/// Visual: capsule PillCard sibling to the tabs card and results card —
/// same Tier-1 clay frame composition as the launcher and recorder pills.
PillCard {
    id: root

    required property bool isTextTab
    required property int padding
    required property int entryCount
    required property int confirmTimeout

    /// Current raw search text (alias to internal text field).
    property alias text: search.text

    /// Debounced search text — updated 150ms after the last keystroke.
    /// Read by Content.qml for entry filtering.
    readonly property string debouncedText: _debouncedText

    /// Focus target for FocusManager (the text field itself).
    readonly property alias focusTarget: search

    /// Natural height of search bar (used by Content.qml to expand
    /// contentWrapper on Images tab by the collapsed amount).
    readonly property real naturalHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight, clearIcon.implicitHeight)

    signal accepted
    signal navigateUp
    signal navigateDown
    signal requestClose
    signal requestTabCycle
    signal clearAllRequested

    function clear(): void {
        search.text = "";
        _confirmClear = false;
    }

    // ── Internal state ────────────────────────────────────────────

    property string _debouncedText: ""
    property bool _confirmClear: false

    Timer {
        id: searchDebounce
        interval: 150
        onTriggered: root._debouncedText = search.text
    }

    Timer {
        id: confirmTimer
        interval: root.confirmTimeout
        onTriggered: root._confirmClear = false
    }

    // ── Layout ────────────────────────────────────────────────────

    // clipContent (not clip) so the PillCard's outer shadows still paint
    // freely — only the inner cardBody clips, which hides children during
    // the implicitHeight 0 ↔ naturalHeight collapse animation.
    clipContent: true
    visible: implicitHeight > 0
    radius: Appearance.rounding.full

    implicitHeight: root.isTextTab ? naturalHeight : 0

    Behavior on implicitHeight {
        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    MaterialIcon {
        id: searchIcon

        visible: root.isTextTab
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.padding

        text: "search"
        color: Colours.palette.m3onSurfaceVariant
    }

    StyledTextField {
        id: search

        visible: root.isTextTab
        anchors.left: searchIcon.right
        anchors.right: clearIcon.left
        anchors.leftMargin: Appearance.spacing.small
        anchors.rightMargin: Appearance.spacing.small

        topPadding: Appearance.padding.larger
        bottomPadding: Appearance.padding.larger

        placeholderText: qsTr("Search clipboard...")

        onTextChanged: searchDebounce.restart()
        onAccepted: root.accepted()

        Keys.onUpPressed: root.navigateUp()
        Keys.onDownPressed: root.navigateDown()
        Keys.onEscapePressed: root.requestClose()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab) {
                root.requestTabCycle();
                event.accepted = true;
            }
        }
    }

    // Clear search / Clear all button (text tab only)
    MaterialIcon {
        id: clearIcon

        visible: root.isTextTab
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.padding

        width: (search.text || root.entryCount > 0) ? implicitWidth : implicitWidth / 2
        opacity: {
            if (!search.text && root.entryCount === 0)
                return 0;
            if (clearMouse.pressed)
                return 0.7;
            if (clearMouse.containsMouse)
                return 1;
            return 0.5;
        }

        text: {
            if (search.text)
                return "close";
            if (root._confirmClear)
                return "warning";
            return "delete_sweep";
        }
        color: root._confirmClear ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

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

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.small
            }
        }

        MouseArea {
            id: clearMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (search.text) {
                    search.text = "";
                    search.forceActiveFocus();
                } else if (root._confirmClear) {
                    root.clearAllRequested();
                    root._confirmClear = false;
                } else {
                    root._confirmClear = true;
                    confirmTimer.restart();
                }
            }
        }
    }
}
