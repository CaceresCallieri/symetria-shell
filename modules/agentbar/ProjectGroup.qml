pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Per-project pill: glassmorphism container with project name and agent chips.
StyledRect {
    id: root

    required property string project
    required property var agents  // Array of agent objects for this project

    readonly property var glassStyle: Colours.glassmorphism(
        Colours.palette.m3surfaceContainerHigh,
        Colours.glass.subtle
    )

    color: glassStyle.background
    radius: Appearance.rounding.full
    border.width: 1
    border.color: glassStyle.border
    clip: true

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
