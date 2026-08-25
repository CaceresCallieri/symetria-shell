pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property Item bar
    required property Item agentBar

    anchors.fill: parent

    StyledRect {
        anchors.fill: parent
        color: Colours.generalBackground

        layer.enabled: true
        layer.effect: MultiEffect {
            maskSource: mask
            maskEnabled: true
            maskInverted: true
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Config.border.sideThickness
            anchors.rightMargin: Config.border.sideThickness
            anchors.topMargin: root.bar.implicitHeight
            anchors.bottomMargin: root.agentBar.implicitHeight
            // Left corners rounded by Border, right corners handled by Backgrounds
            topLeftRadius: Config.border.rounding
            bottomLeftRadius: Config.border.rounding
        }
    }
}
