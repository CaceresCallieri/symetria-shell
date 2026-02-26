pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import QtQuick
import QtQuick.Layouts

/// Per-project pill: glassmorphism container with project name and agent chips.
StyledRect {
    id: root

    required property string project
    required property var agents  // Array of agent objects for this project

    // Workspace badge: pick representative workspace for this group
    readonly property var wsInfo: AgentService.workspaceForAgents(agents)
    readonly property string wsIcon: wsInfo ? AgentService.workspaceIconForWsId(wsInfo.id) : ""
    readonly property var parsedWsIcon: wsIcon ? Icons.parseIcon(wsIcon) : null
    readonly property bool hasWsBadge: parsedWsIcon !== null && parsedWsIcon.iconText !== ""

    // Active when this group's workspace matches the focused workspace
    readonly property bool isCurrentProject: wsInfo !== null && wsInfo.id === Hypr.activeWsId

    onWsInfoChanged: console.log(`[ProjectGroup] "${project}" wsInfo changed:`, JSON.stringify(wsInfo))
    onIsCurrentProjectChanged: console.log(`[ProjectGroup] "${project}" isCurrentProject:`, isCurrentProject,
        "wsInfo:", JSON.stringify(wsInfo), "activeWsId:", Hypr.activeWsId)

    Component.onCompleted: console.log(`[ProjectGroup] "${project}" INIT: wsInfo=`, JSON.stringify(wsInfo),
        "activeWsId=", Hypr.activeWsId, "isCurrentProject=", isCurrentProject)

    readonly property var activeGlass: Colours.glassmorphism(Colours.palette.m3primary, 1.0)
    readonly property var inactiveGlass: Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, 0.15)

    color: isCurrentProject ? activeGlass.background : inactiveGlass.background
    radius: Appearance.rounding.full
    border.width: 1
    border.color: isCurrentProject
        ? Qt.alpha(Colours.palette.m3primary, 0.85)
        : inactiveGlass.border
    clip: true

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    implicitHeight: Config.agentbar.sizes.innerHeight
    implicitWidth: content.implicitWidth

    Behavior on implicitWidth {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
    }

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        // Left padding
        Item {
            implicitWidth: Appearance.spacing.smaller
            implicitHeight: 1
        }

        // Workspace badge (Roman numeral or Material icon)
        Loader {
            id: wsBadge

            active: root.hasWsBadge
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: root.parsedWsIcon?.useMaterial ? wsMatIcon : wsTextIcon

            Component {
                id: wsMatIcon

                MaterialIcon {
                    text: root.parsedWsIcon?.iconText ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.small - 2
                }
            }

            Component {
                id: wsTextIcon

                StyledText {
                    text: root.parsedWsIcon?.iconText ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font.weight: Font.DemiBold
                    font.pointSize: Appearance.font.size.small - 2
                }
            }
        }

        // Project name label
        StyledText {
            text: root.project
            color: Colours.palette.m3primary
            font.weight: Font.Bold
            font.pointSize: Appearance.font.size.small
        }

        // Agent chips
        Repeater {
            model: root.agents

            AgentChip {
                required property var modelData
                required property int index

                instanceNum: index + 1
                title: modelData.title ?? ""
                dotColor: AgentService.colorForIndex(modelData.color_idx ?? 0)
                active: modelData.active ?? false
            }
        }

        // Right padding
        Item {
            implicitWidth: Appearance.spacing.smaller
            implicitHeight: 1
        }
    }
}
