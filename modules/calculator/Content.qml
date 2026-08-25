pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Main content for the calculator drawer.
///
/// Layout (top to bottom):
/// - Live result display
/// - Input field with copy button
///
/// Note: History feature is shelved for now (see commented sections below)
Item {
    id: root

    required property PersistentProperties visibilities
    required property var panels
    required property real maxHeight

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Focus management - expression persists across drawer open/close
    FocusManager {
        active: root.visibilities.calculator
        target: input
        onOpen: () => {
            // Always restore from Calculator service - it's the source of truth.
            // Unconditional assignment avoids race conditions in rapid open/close.
            input.text = Calculator.currentExpression;
        }
        // Note: onClose intentionally does NOT clear - expression persists within session
    }

    implicitWidth: Config.calculator.sizes.width + padding * 2
    implicitHeight: Math.min(root.maxHeight, (resultSection.visible ? resultSection.implicitHeight + padding : 0) + inputSection.implicitHeight + padding * 2)

    /*
    // ============================================================
    // HISTORY SECTION - Shelved for future implementation
    // ============================================================
    // Double-click confirmation state for clear all
    property bool confirmClear: false

    // History section (top)
    Item {
        id: historySection

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: Math.min(
            Config.calculator.sizes.historyItemHeight * Config.calculator.sizes.maxVisibleHistory,
            historyList.contentHeight > 0 ? historyList.contentHeight + Appearance.spacing.normal : emptyState.implicitHeight
        )

        // History list
        StyledListView {
            id: historyList

            visible: Calculator.history.length > 0
            model: Calculator.history
            width: Config.calculator.sizes.width
            height: parent.implicitHeight
            clip: true
            spacing: Appearance.spacing.small
            topMargin: Appearance.spacing.normal
            orientation: Qt.Vertical
            reuseItems: true

            delegate: HistoryItem {
                required property var modelData
                required property int index

                entry: modelData
                itemIndex: index
                visibilities: root.visibilities

                onDeleteRequested: idx => Calculator.removeEntry(idx)
                onLoadRequested: idx => {
                    Calculator.loadFromHistory(idx);
                    input.text = Calculator.currentExpression;
                    input.forceActiveFocus();
                }
            }

            move: Transition {
                Anim { property: "y" }
            }

            add: Transition {
                Anim {
                    properties: "opacity,scale"
                    from: 0
                    to: 1
                }
            }

            remove: Transition {
                Anim {
                    properties: "opacity,scale"
                    from: 1
                    to: 0
                }
            }

            displaced: Transition {
                Anim { property: "y" }
                Anim {
                    properties: "opacity,scale"
                    to: 1
                }
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: historyList
            }
        }

        // Empty state
        Row {
            id: emptyState

            visible: Calculator.history.length === 0
            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            MaterialIcon {
                text: "history"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.extraLarge

                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: qsTr("No calculation history")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.larger
                    font.weight: 500
                }

                StyledText {
                    text: qsTr("Press Enter to save calculations")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.normal
                }
            }
        }
    }

    // Confirmation timeout for clear all
    Timer {
        id: confirmTimer
        interval: 2000
        onTriggered: root.confirmClear = false
    }
    // ============================================================
    // END HISTORY SECTION
    // ============================================================
    */

    // Result display - shows only the result, input is source of truth for expression
    StyledRect {
        id: resultSection

        visible: Calculator.currentExpression  // Only show when there's something to calculate
        color: Colours.layer(Colours.palette.m3surfaceContainerLow, 1)
        radius: Appearance.rounding.normal

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: resultRow.implicitHeight + Appearance.padding.larger * 2

        RowLayout {
            id: resultRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Appearance.padding.larger
            spacing: Appearance.spacing.normal

            // Error state test expressions:
            // - Invalid syntax: "2++2", "sqrt(", "1/0"
            // - Check Qalculator output for exact error format
            MaterialIcon {
                text: Calculator.hasError ? "error" : "drag_handle"
                color: Calculator.hasError ? Colours.palette.m3error : Colours.palette.m3primary
                font.pointSize: Appearance.font.size.large
                Layout.alignment: Qt.AlignVCenter

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.small
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                text: Calculator.currentResult
                color: Calculator.hasError ? Colours.palette.m3error : Colours.palette.m3primary
                font.pointSize: Appearance.font.size.larger
                font.weight: Font.Bold
                wrapMode: Text.Wrap  // Keep wrap in case of very large numbers

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.small
                    }
                }
            }
        }
    }

    // Debounce timer for evaluation - prevents lag from evaluating every keystroke
    Timer {
        id: evalDebounce
        interval: 150
        onTriggered: Calculator.evaluate(input.text)
    }

    // Input section (bottom)
    StyledRect {
        id: inputSection

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Appearance.rounding.full

        anchors.top: resultSection.visible ? resultSection.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: Math.max(inputIcon.implicitHeight, input.implicitHeight, clearIcon.implicitHeight)

        MaterialIcon {
            id: inputIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.padding

            text: "calculate"
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: input

            anchors.left: inputIcon.right
            anchors.right: clearIcon.left
            anchors.leftMargin: Appearance.spacing.small
            anchors.rightMargin: Appearance.spacing.small

            topPadding: Appearance.padding.larger
            bottomPadding: Appearance.padding.larger

            placeholderText: qsTr("Type expression (e.g., 2+2, sqrt(144))")

            onTextChanged: {
                Calculator.currentExpression = text;
                evalDebounce.restart();  // Debounce instead of direct evaluation
            }

            onAccepted: {
                // Copy result on Enter if enabled in config and there's a valid result
                if (Config.calculator.copyOnEnter && Calculator.currentExpression && !Calculator.hasError && Calculator.currentResult) {
                    Calculator.copyResult();
                }
            }

            Keys.onEscapePressed: root.visibilities.calculator = false

            Keys.onPressed: event => {
                // Ctrl+C to copy result (when no text selected)
                if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                    if (selectedText === "" && Calculator.currentResult && !Calculator.hasError) {
                        Calculator.copyResult();
                        event.accepted = true;
                    }
                }
            }
        }

        // Clear input button
        MaterialIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding

            width: input.text ? implicitWidth : implicitWidth / 2
            opacity: {
                if (!input.text)
                    return 0;
                if (clearArea.pressed)
                    return 0.7;
                if (clearArea.containsMouse)
                    return 1;
                return 0.5;
            }

            text: "close"
            color: Colours.palette.m3onSurfaceVariant

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

            MouseArea {
                id: clearArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    input.text = "";
                    input.forceActiveFocus();
                }
            }
        }
    }

    Behavior on implicitWidth {
        enabled: root.visibilities.calculator

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    Behavior on implicitHeight {
        enabled: root.visibilities.calculator

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }
}
