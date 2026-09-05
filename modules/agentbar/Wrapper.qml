pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Animated bottom bar container for the agent bar, embedded in the unified
/// Drawers surface. Mirrors bar/Wrapper.qml but for the bottom edge.
///
/// When Mesura Code has projects with threads, expands upward from the bottom
/// screen edge to reveal AgentBarContent. When nothing is connected, collapses
/// to height 0 (no bottom presence).
///
/// There used to be a second layout here — a merged workspace+agent bar driven
/// by `AgentService` — selected by `Config.agentbar.mergeWorkspaces`. It was
/// organised BY Hyprland workspace, and a Mesura thread has no window and
/// therefore no workspace, so it went out with Symmetria IDE rather than being
/// carried forward with nothing to put in it.
///
/// Key properties consumed by the drawers system:
///   - implicitHeight: flows into mask Region, Border, Backgrounds, Panels, Interactions
///   - exclusiveZone: consumed by Exclusions.qml for the bottom ExclusionZone
Item {
    id: root

    required property ShellScreen screen

    readonly property int padding: Math.max(Appearance.padding.small, Config.border.thickness)
    readonly property int innerHeight: Config.agentbar.sizes.innerHeight
    readonly property int contentHeight: innerHeight + padding * 2
    // Snaps immediately so application windows shift before the visual animation completes
    // (matches bar/Wrapper behavior — prevents content from being momentarily obscured)
    readonly property int exclusiveZone: shouldBeVisible ? contentHeight : 0
    readonly property bool shouldBeVisible: (Config.agentbar.enabled && SymmetriaThreads.projectGroups.length > 0 && !Visibilities.agentBarHidden) || preview.previewActive

    clip: true
    visible: height > 0
    implicitHeight: 0

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

        sourceComponent: AgentBarContent {
            height: root.contentHeight
        }
    }

    Component.onCompleted: {
        Visibilities.agentBars.set(screen, this);
        Visibilities.agentBarsVersion++;
    }
    Component.onDestruction: {
        Visibilities.agentBars.delete(screen);
        Visibilities.agentBarsVersion++;
    }

    // Right-aligned sprite preview (controlled by /test-sprite skill)
    SpritePreview {
        id: preview
        anchors.right: parent.right
        anchors.rightMargin: Appearance.padding.large
        anchors.verticalCenter: parent.verticalCenter
    }
}
