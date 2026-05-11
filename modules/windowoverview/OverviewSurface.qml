pragma ComponentBehavior: Bound

import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

/// Layer-shell surface for the Window Overview feature.
///
/// One window per screen via Variants. Only the variant whose monitor matches
/// WindowOverviewService.targetMonitor sets shouldShow=true and maps; the rest
/// stay unmapped at zero cost.
///
/// Full feature: dimmed scrim, letter-label tile grid, keyboard dispatch (A–P +
/// Return for 16 slots), click-to-focus for overflow tiles, Esc-dismiss, and
/// reactive tile rebuild with auto-close on workspace/monitor change.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool shouldShow: WindowOverviewService.active && WindowOverviewService.targetMonitor === Hypr.monitorFor(modelData)

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
                    WindowOverviewService.hide();
                }

                // Letter dispatch: A-Z and Return/Enter route to service.activate().
                // Reject keypresses with Ctrl/Alt/Meta to avoid swallowing user shortcuts;
                // Shift is permitted (caps-lock-on or held-shift typing still resolves).
                Keys.onPressed: event => {
                    const blockedMods = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
                    if (event.modifiers & blockedMods)
                        return;

                    let letter = "";
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        letter = "Return";
                    else if (event.text && /^[a-zA-Z]$/.test(event.text))
                        letter = event.text.toUpperCase();
                    else
                        return;

                    event.accepted = true;
                    WindowOverviewService.activate(letter);
                }

                // Dimmed scrim — pushes tiles to visual focus.
                Rectangle {
                    anchors.fill: parent
                    color: Colours.palette.m3scrim
                    opacity: 0.65
                }

                // Tile grid container — uniform-cell grid with letterboxed tiles.
                Item {
                    id: gridContainer

                    anchors.fill: parent
                    anchors.margins: Appearance.padding.larger * 2

                    readonly property int tileCount: WindowOverviewService.tiles.length
                    readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(tileCount)))
                    readonly property int rows: Math.max(1, Math.ceil(tileCount / cols))
                    readonly property real gap: Appearance.spacing.large
                    readonly property real cellW: tileCount > 0 ? (width - gap * (cols - 1)) / cols : 0
                    readonly property real cellH: tileCount > 0 ? (height - gap * (rows - 1)) / rows : 0

                    Grid {
                        anchors.centerIn: parent
                        columns: gridContainer.cols
                        spacing: gridContainer.gap

                        Repeater {
                            model: WindowOverviewService.tiles

                            Tile {
                                required property var modelData

                                tileData: modelData
                                cellWidth: gridContainer.cellW
                                cellHeight: gridContainer.cellH
                            }
                        }
                    }
                }
            }
        }
    }
}
