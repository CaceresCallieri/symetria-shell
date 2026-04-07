pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick

/// Shared workspace app icons for bar and agentbar.
/// Delegates window processing to AppIconsProcessor; handles event-driven updates.
Row {
    id: root

    required property int workspaceId

    /// Whether grouped-window pill containers animate their own implicitWidth.
    /// Set false when an outer container already animates the total width (e.g.,
    /// agentbar's MergedBarContent Layout.preferredWidth Behavior), to avoid double-easing.
    property bool animateGroupWidth: true

    spacing: Appearance.padding.small
    visible: cachedModel.length > 0
    height: Config.bar.sizes.indicatorHeight

    // Events that affect window positions, lifecycle, or grouping (Set for O(1) lookup)
    // activewindowv2 included because Hyprland 0.54+ doesn't emit togglegroup events;
    // focus changes are the closest proxy. modelsEqual() prevents unnecessary rerenders.
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

    // Use debounce for all initialization paths to prevent race conditions
    Component.onCompleted: updateDebounce.restart()
    onWorkspaceIdChanged: updateDebounce.restart()

    // Debounce timer - coalesces rapid Hyprland events into single update
    // 50ms chosen empirically: fast enough for responsive UI, slow enough to batch
    // rapid event bursts (e.g., togglegroup emits multiple events in quick succession)
    Timer {
        id: updateDebounce
        interval: 50
        onTriggered: root.updateClients()
    }

    // Listen to Hyprland events - only update on relevant events
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root.windowLayoutEvents.has(event.name))
                updateDebounce.restart();
        }
    }

    // Move animation only - entry animation handled by individual icons via animateEntry
    // (Grouped containers are recreated on model change, so Row add transition would
    // cause all grouped items to animate on every update)
    move: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.cachedModel
        }

        // Delegate: conditionally render grouped container or single icon
        Loader {
            // NOTE: `required property var` is correct here — NOT `required modelData`.
            // Loader has no inherited modelData property; the Repeater injects it as a
            // context property. With ComponentBehavior: Bound, inner Components can only
            // access real properties, not context properties. Declaring the property makes
            // it real and accessible to sourceComponent children. (See docs/qml-pitfalls.md)
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

                // Pill-shaped container for grouped windows (matching AGS style)
                Rectangle {
                    id: container

                    // Pill styling (subtle intensity for background element)
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

                    // Smooth width animation when icons are added/removed.
                    // Disabled when the outer container already animates width
                    // (e.g., agentbar's MergedBarContent Layout.preferredWidth Behavior).
                    Behavior on implicitWidth {
                        enabled: root.animateGroupWidth
                        Anim {}
                    }

                    Row {
                        id: groupRow
                        anchors.centerIn: parent
                        spacing: Appearance.padding.small

                        // No add/move transitions - container is recreated on model change
                        // so all icons would animate on every update

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
