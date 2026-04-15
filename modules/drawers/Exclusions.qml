pragma ComponentBehavior: Bound

import qs.components.containers
import qs.config
import Quickshell
import QtQuick

Scope {
    id: root

    required property ShellScreen screen
    required property Item bar
    required property Item agentBar

    ExclusionZone {
        anchors.top: true
        exclusiveZone: root.bar.exclusiveZone
    }

    ExclusionZone {
        anchors.left: true
        exclusiveZone: Config.border.sideThickness
    }

    ExclusionZone {
        anchors.right: true
        exclusiveZone: Config.border.sideThickness
    }

    ExclusionZone {
        anchors.bottom: true
        exclusiveZone: root.agentBar.exclusiveZone
    }

    component ExclusionZone: StyledWindow {
        screen: root.screen
        name: "border-exclusion"
        exclusiveZone: 0
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
}
