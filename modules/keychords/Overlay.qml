pragma ComponentBehavior: Bound

import qs.components
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Centered floating dialog for KeyChords which-key display.
///
/// Shows available chord keys for the active group. All keyboard
/// input is captured — matched keys execute commands, Escape dismisses,
/// unmatched keys are silently consumed. Click outside dismisses via
/// HyprlandFocusGrab (in Drawers.qml) or the transparent catch area.
///
/// Lives as a direct child of StyledWindow in Drawers.qml (not inside
/// Panels) to avoid Region mask issues with click-through.
Item {
    id: root

    required property PersistentProperties visibilities

    readonly property bool shouldShow: visibilities.keychords && Config.keychords.enabled && KeyChordsService.active

    visible: dialogScale > 0

    // Animated properties driven by shouldShow state.
    // IMPORTANT: The idle value MUST be 0.0, not 0.01 or any positive number.
    // When dialogScale > 0, this Item is visible: true, which means its
    // full-window dismiss MouseArea participates in Qt Quick's cursor
    // hit-testing — even with enabled: false. Being the highest z-order
    // sibling in Drawers.qml, its default ArrowCursor shadows every
    // cursorShape below (buttons, tray items, etc.), preventing pointer
    // cursors from ever reaching the Wayland cursor-shape-v1 protocol.
    // See: docs/cursor-shape-layer-shell.md
    property real dialogScale: shouldShow ? 1.0 : 0.0
    property real dialogOpacity: shouldShow ? 1.0 : 0.0

    Behavior on dialogScale {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutBack
            easing.overshoot: 1.5
        }
    }

    Behavior on dialogOpacity {
        Anim {}
    }

    FocusManager {
        active: root.shouldShow
        target: dialog
    }

    // Transparent click catcher — dismiss when clicking outside the dialog.
    // Only enabled when the dialog is showing to avoid blocking click events.
    // Note: enabled: false does NOT prevent cursor shadowing — that is handled
    // by the parent Item's visible: dialogScale > 0 gate, which removes this
    // entire subtree from Qt Quick's cursor hit-testing when idle.
    MouseArea {
        anchors.fill: parent
        enabled: root.shouldShow
        onClicked: KeyChordsService.dismiss()
    }

    // Centered dialog container
    Item {
        id: dialogWrapper

        anchors.centerIn: parent
        width: dialog.implicitWidth
        height: dialog.implicitHeight

        scale: root.dialogScale
        opacity: root.dialogOpacity

        StyledRect {
            id: dialog

            implicitWidth: dialogContent.implicitWidth + Appearance.padding.large * 6
            implicitHeight: dialogContent.implicitHeight + Appearance.padding.large * 6

            readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

            radius: Appearance.rounding.normal
            color: glassStyle.background
            border.width: 1
            border.color: glassStyle.border

            focus: true

            Keys.onPressed: event => {
                event.accepted = true;
                if (event.text && event.text.length > 0)
                    KeyChordsService.handleKey(event.text);
            }

            Keys.onEscapePressed: event => {
                event.accepted = true;
                KeyChordsService.dismiss();
            }

            ColumnLayout {
                id: dialogContent

                anchors.centerIn: parent
                spacing: Appearance.spacing.large

                // Group title
                StyledText {
                    Layout.alignment: Qt.AlignHCenter

                    text: KeyChordsService.activeGroupTitle
                    font.pointSize: Appearance.font.size.large
                    font.weight: Font.DemiBold
                    color: Colours.palette.m3onSurface
                }

                // Chord keys grid
                Grid {
                    Layout.alignment: Qt.AlignHCenter

                    columns: 2
                    columnSpacing: Appearance.spacing.small
                    rowSpacing: Appearance.spacing.normal

                    Repeater {
                        model: KeyChordsService.activeChords

                        ChordKey {
                            required property var modelData

                            keyLetter: modelData.key
                            label: modelData.label

                            // Each chord key takes equal share of the row
                            width: (Config.keychords.sizes.maxWidth - Appearance.spacing.small) / 2

                            onActivated: {
                                KeyChordsService.dismiss();
                                KeyChordsService.executeCommand(modelData.command);
                            }
                        }
                    }
                }
            }
        }
    }
}
