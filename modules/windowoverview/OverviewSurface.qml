pragma ComponentBehavior: Bound

import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

/// Transparent keyboard layer for the Dwindle window navigator.
///
/// The compositor continues to render the real workspace below this surface.
/// Each Tile binds to one real client rectangle and adds only its navigation
/// label, app icon, title, and selection hit target.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool shouldShow: WindowOverviewService.sessionActive
                && WindowOverviewService.targetMonitorName === (Hypr.monitorFor(modelData)?.name ?? "")

            screen: modelData
            name: "windowoverview-surface"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            visible: shouldShow
            mask: inputRegion

            Region {
                id: inputRegion
                x: 0
                y: 0
                width: win.shouldShow ? win.width : 0
                height: win.shouldShow ? win.height : 0
            }

            FocusManager {
                active: win.shouldShow
                target: surface
            }

            FocusScope {
                id: surface

                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: event => {
                    event.accepted = true;
                    WindowOverviewService.cancel();
                }

                // Ignore held launcher modifiers. Shift remains valid so Caps
                // Lock and shifted letters resolve to the same frozen label.
                Keys.onPressed: event => {
                    const blockedMods = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
                    if (event.modifiers & blockedMods)
                        return;

                    let label = "";
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        label = "Return";
                    else if (event.text && /^[a-zA-Z]$/.test(event.text))
                        label = event.text.toUpperCase();
                    else
                        return;

                    event.accepted = true;
                    WindowOverviewService.activate(label);
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: WindowOverviewService.cancel()
                }

                Repeater {
                    model: WindowOverviewService.tiles

                    Tile {
                        required property var modelData

                        tileData: modelData
                        screen: win.modelData
                    }
                }
            }
        }
    }
}
