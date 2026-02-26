pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Horizontal layout of project group pills.
Item {
    id: root

    implicitHeight: Config.agentbar.sizes.innerHeight
    implicitWidth: layout.implicitWidth

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        Repeater {
            model: AgentService.projects

            ProjectGroup {
                required property string modelData

                project: modelData
                agents: AgentService.agents.filter(a => a.project === modelData)
            }
        }
    }
}
