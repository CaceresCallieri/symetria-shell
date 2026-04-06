pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

/// App icons for the merged bar's active workspace pill.
/// Uses shared ClientAppIcon from qs.components.
Row {
    id: root

    required property int workspaceId

    spacing: Appearance.padding.small
    visible: cachedModel.length > 0
    height: Config.bar.sizes.indicatorHeight

    readonly property var windowLayoutEvents: new Set([
        "openwindow", "closewindow",
        "movewindow", "movewindowv2",
        "togglegroup", "moveintogroup", "moveoutofgroup",
        "activewindowv2", "changegroupactive"
    ])

    property var cachedModel: []

    function updateClients(): void {
        const result = AppIconsProcessor.processClients(root.workspaceId, Hypr.toplevels.values);
        if (!AppIconsProcessor.modelsEqual(result, root.cachedModel))
            root.cachedModel = result;
    }

    Component.onCompleted: updateDebounce.restart()
    onWorkspaceIdChanged: updateDebounce.restart()

    Timer {
        id: updateDebounce
        interval: 50
        onTriggered: root.updateClients()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root.windowLayoutEvents.has(event.name))
                updateDebounce.restart();
        }
    }

    move: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.cachedModel
        }

        Loader {
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: modelData.isGroup ? groupedContainer : singleIcon

            Component {
                id: singleIcon

                ClientAppIcon {
                    client: modelData.clients[0]
                }
            }

            Component {
                id: groupedContainer

                Rectangle {
                    readonly property var glassStyle: Colours.pillStyle(
                        Colours.palette.m3surfaceContainerHigh,
                        Colours.glass.subtle
                    )

                    implicitWidth: groupRow.implicitWidth + Appearance.padding.normal * 2
                    implicitHeight: Config.bar.sizes.indicatorHeight

                    color: glassStyle.background
                    radius: Appearance.rounding.full
                    border.width: 1
                    border.color: glassStyle.border

                    // No Behavior on implicitWidth here — the outer Layout.preferredWidth
                    // Behavior in MergedBarContent.qml is the canonical width animator for the
                    // whole pill. An inner animation on the group container would double-ease
                    // (same reason Workspace.qml uses animateWindowsWidth: false).
                    Row {
                        id: groupRow
                        anchors.centerIn: parent
                        spacing: Appearance.padding.small

                        Repeater {
                            model: modelData.clients

                            ClientAppIcon {
                                required property var modelData
                                client: modelData
                                animateEntry: false
                            }
                        }
                    }
                }
            }
        }
    }
}
