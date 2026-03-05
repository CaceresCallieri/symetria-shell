pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Animated bottom bar container for the agent bar, embedded in the unified
/// Drawers surface. Mirrors BarWrapper.qml but for the bottom edge.
///
/// When agents are active, expands upward from the bottom border strip to
/// reveal AgentBarContent. When no agents are connected, collapses back to
/// Config.border.thickness (the normal bottom border).
///
/// Key properties consumed by the drawers system:
///   - implicitHeight: flows into mask Region, Border, Backgrounds, Panels, Interactions
///   - exclusiveZone: consumed by Exclusions.qml for the bottom ExclusionZone
Item {
    id: root

    readonly property int padding: Math.max(Appearance.padding.small, Config.border.thickness)
    readonly property int contentHeight: Config.agentbar.sizes.innerHeight + padding * 2
    // Snaps immediately so application windows shift before the visual animation completes
    // (matches BarWrapper behavior — prevents content from being momentarily obscured)
    readonly property int exclusiveZone: shouldBeVisible ? contentHeight : Config.border.thickness
    readonly property bool shouldBeVisible: Config.agentbar.enabled && AgentService.agentCount > 0

    visible: height > Config.border.thickness
    implicitHeight: Config.border.thickness

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitHeight: root.contentHeight
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitHeight"
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitHeight"
                easing.bezierCurve: Appearance.anim.curves.emphasized
            }
        }
    ]

    Loader {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        active: root.visible

        sourceComponent: AgentBarContent {
            height: root.contentHeight
        }
    }
}
