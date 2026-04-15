pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

/// Standalone KeyChords overlay on WlrLayer.Overlay.
///
/// Renders above fullscreen windows (unlike the former drawer-embedded overlay on WlrLayer.Top).
/// Shows available chord keys for the active group in a multi-column grid that adapts to content
/// size. Positioned above the agent bar, centered horizontally. Slides up from below on show.
/// Keyboard Escape navigates back; clicking outside dismisses.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "keychords-overlay"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // Exclusive so the overlay grabs keyboard input immediately on map.
            // Window is unmapped (visible: false) when hidden, so Exclusive doesn't
            // steal focus when the overlay is inactive.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Window maps when shouldShow triggers, unmaps after fade-out completes.
            // This ensures Exclusive keyboard focus only applies while the overlay is on screen.
            visible: win.shouldShow || win.dialogOpacity > 0

            // Full-window input when active (for dismiss MouseArea), click-through when hidden.
            mask: inputRegion

            Region {
                id: inputRegion
                x: 0
                y: 0
                width: win.shouldShow ? win.width : 0
                height: win.shouldShow ? win.height : 0
            }

            // Show only on the monitor that was focused when the chord was triggered.
            // Decoupled from Drawers' PersistentProperties — uses service state directly
            // to avoid HyprlandFocusGrab clearing the visibility flag.
            readonly property bool shouldShow: Config.keychords.enabled && KeyChordsService.active && KeyChordsService.targetMonitor === Hypr.monitorFor(modelData)

            onShouldShowChanged: console.warn("[KeyChords:Overlay]", modelData.name, "shouldShow:", shouldShow,
                "| enabled:", Config.keychords.enabled,
                "| service.active:", KeyChordsService.active,
                "| targetMonitor:", KeyChordsService.targetMonitor?.name ?? "null",
                "| myMonitor:", Hypr.monitorFor(modelData)?.name ?? "null")
            onVisibleChanged: console.warn("[KeyChords:Overlay]", modelData.name, "window visible:", visible,
                "| dialogOpacity:", dialogOpacity, "| shouldShow:", shouldShow)

            Component.onCompleted: console.warn("[KeyChords:Overlay]", modelData.name, "window created",
                "| monitor:", Hypr.monitorFor(modelData)?.name ?? "null")

            // Agent bar reference for bottom offset positioning.
            // Reactive via agentBarsVersion — resolves correctly even when agent bars register
            // after this overlay (onCompleted order is not guaranteed across Variants).
            readonly property Item agentBarRef: {
                void Visibilities.agentBarsVersion;
                return Visibilities.agentBars.get(modelData) ?? null;
            }
            readonly property real bottomOffset: agentBarRef?.implicitHeight ?? 0

            // IMPORTANT: The idle value of dialogOpacity MUST reach 0.0 so visible becomes false.
            // When visible: true, the full-window dismiss MouseArea participates in Qt Quick's
            // cursor hit-testing — even with enabled: false. Being the highest z-order sibling,
            // its default ArrowCursor shadows every cursorShape below.
            // Note: enabled: false alone does NOT prevent cursor shadowing — visible: dialogOpacity > 0
            // is the actual guard. See: docs/cursor-shape-layer-shell.md
            property real dialogOpacity: shouldShow ? 1.0 : 0.0
            // Use a fixed 200px fallback when dialogWrapper.height is 0 (before first layout pass),
            // so the slide-in animation has a non-zero starting offset.
            property real dialogTranslateY: shouldShow ? 0 : (dialogWrapper.height > 0 ? dialogWrapper.height + bottomOffset : 200 + bottomOffset)

            Behavior on dialogOpacity {
                Anim {}
            }

            Behavior on dialogTranslateY {
                NumberAnimation {
                    duration: Appearance.anim.durations.normal
                    easing.type: Easing.OutCubic
                }
            }

            FocusManager {
                active: win.shouldShow
                target: dialog
                onOpen: () => console.warn("[KeyChords:Overlay]", win.modelData.name, "FocusManager: focus granted to dialog")
                onClose: () => console.warn("[KeyChords:Overlay]", win.modelData.name, "FocusManager: focus released")
            }

            // Transparent click catcher — dismiss when clicking outside the dialog.
            MouseArea {
                anchors.fill: parent
                visible: win.dialogOpacity > 0
                enabled: win.shouldShow
                onClicked: KeyChordsService.dismiss()
            }

            // Bottom-centered dialog — sized by content, not by screen
            Item {
                id: dialogWrapper

                anchors.bottom: parent.bottom
                anchors.bottomMargin: win.bottomOffset
                anchors.horizontalCenter: parent.horizontalCenter
                width: dialog.implicitWidth
                height: dialog.implicitHeight

                transform: Translate {
                    y: win.dialogTranslateY
                }
                opacity: win.dialogOpacity

                StyledRect {
                    id: dialog

                    implicitWidth: dialogContent.implicitWidth + Appearance.padding.large * 2
                    implicitHeight: dialogContent.implicitHeight + Appearance.padding.large * 2

                    readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

                    radius: Appearance.rounding.normal
                    color: glassStyle.background
                    border.width: 1
                    border.color: glassStyle.border

                    focus: true

                    Keys.onPressed: event => {
                        console.warn("[KeyChords:Overlay] Key pressed:", event.text, "| key:", event.key, "| focus:", dialog.activeFocus);
                        event.accepted = true;
                        if (event.text && event.text.length > 0)
                            KeyChordsService.handleKey(event.text);
                    }

                    Keys.onEscapePressed: event => {
                        console.warn("[KeyChords:Overlay] Escape pressed");
                        event.accepted = true;
                        KeyChordsService.navigateBack();
                    }

                    ColumnLayout {
                        id: dialogContent

                        anchors.centerIn: parent
                        spacing: Appearance.spacing.normal

                        // Group title
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter

                            text: KeyChordsService.activeGroupTitle
                            font.pointSize: Appearance.font.size.normal
                            font.weight: Font.DemiBold
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        // Chord keys grid — columns computed from screen width, container shrinks to fit
                        Grid {
                            id: chordGrid

                            Layout.alignment: Qt.AlignHCenter

                            readonly property real availableWidth: win.width > 0 ? win.width - Appearance.padding.large * 4 : 0
                            columns: Math.max(1, Math.min(
                                KeyChordsService.activeChords.length ?? 1,
                                Math.floor(availableWidth / (Config.keychords.sizes.itemWidth + columnSpacing))
                            ))

                            columnSpacing: Appearance.spacing.small
                            rowSpacing: Appearance.spacing.small

                            Repeater {
                                model: KeyChordsService.activeChords

                                ChordKey {
                                    required property var modelData

                                    keyLetter: modelData.key
                                    label: modelData.label
                                    width: Config.keychords.sizes.itemWidth

                                    onActivated: {
                                        KeyChordsService.dispatchChord(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
