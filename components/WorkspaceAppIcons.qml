pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick

/// Shared workspace app icons for bar and agentbar.
/// The window model (grouping, sorting, event-driven refresh) is provided by the shared
/// headless WorkspaceWindowModel; this component owns only the visual row + animations.
Row {
    id: root

    required property int workspaceId

    /// Whether grouped-window pill containers animate their own implicitWidth.
    /// Set false when an outer container already animates the total width (e.g.,
    /// agentbar's MergedBarContent Layout.preferredWidth Behavior), to avoid double-easing.
    property bool animateGroupWidth: true

    // Shared headless provider: AppIconsProcessor call + debounced event-driven refresh
    // + modelsEqual churn-gate. Single source of truth, also consumed by the agentbar's
    // MergedWindowAgentRow.
    readonly property WorkspaceWindowModel windowModel: WorkspaceWindowModel {
        workspaceId: root.workspaceId
    }

    spacing: Appearance.padding.small
    visible: root.windowModel.model.length > 0
    height: Config.bar.sizes.indicatorHeight

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
            values: root.windowModel.model
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
                    // intentional var: heterogeneous JS { background, border }
                    readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

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
                                required property HyprlandToplevel modelData
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
