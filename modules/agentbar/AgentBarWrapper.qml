pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Animated bottom bar container for the agent bar, embedded in the unified
/// Drawers surface. Mirrors BarWrapper.qml but for the bottom edge.
///
/// When agents are active, expands upward from the bottom border strip to
/// reveal either AgentBarContent (separate mode) or MergedBarContent (merged mode).
/// When no agents are connected, collapses back to Config.border.thickness.
///
/// Key properties consumed by the drawers system:
///   - implicitHeight: flows into mask Region, Border, Backgrounds, Panels, Interactions
///   - exclusiveZone: consumed by Exclusions.qml for the bottom ExclusionZone
Item {
    id: root

    required property ShellScreen screen

    readonly property int padding: Math.max(Appearance.padding.small, Config.border.thickness)
    // Merged mode uses the bar's taller innerWidth since it displays workspace content;
    // separate mode uses the agentbar's compact innerHeight.
    readonly property int innerHeight: AgentService.mergeActive
        ? Config.bar.sizes.innerWidth
        : Config.agentbar.sizes.innerHeight
    readonly property int contentHeight: innerHeight + padding * 2
    // Snaps immediately so application windows shift before the visual animation completes
    // (matches BarWrapper behavior — prevents content from being momentarily obscured)
    readonly property int exclusiveZone: shouldBeVisible ? contentHeight : Config.border.thickness
    readonly property bool shouldBeVisible: (Config.agentbar.enabled && AgentService.agentCount > 0 && !AgentService.userHidden)
        || preview.previewActive

    clip: true
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
        anchors.top: parent.top

        active: root.shouldBeVisible || root.visible

        sourceComponent: AgentService.mergeActive ? mergedContentComponent : separateContentComponent
    }

    Component {
        id: separateContentComponent

        AgentBarContent {
            height: root.contentHeight
        }
    }

    Component {
        id: mergedContentComponent

        MergedBarContent {
            height: root.contentHeight
            screen: root.screen
        }
    }

    // Right-aligned sprite preview (controlled by /test-sprite skill)
    SpritePreview {
        id: preview
        anchors.right: parent.right
        anchors.rightMargin: Appearance.padding.large
        anchors.verticalCenter: parent.verticalCenter
    }
}
