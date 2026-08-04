pragma ComponentBehavior: Bound

import qs.components.effects
import qs.services
import qs.config
import qs.utils
import Quickshell.Services.SystemTray
import QtQuick

MouseArea {
    id: root

    required property SystemTrayItem modelData

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    implicitWidth: Config.bar.sizes.iconSize
    implicitHeight: Config.bar.sizes.iconSize

    onClicked: event => {
        if (event.button === Qt.LeftButton)
            modelData.activate();
        else
            modelData.secondaryActivate();
    }

    ColouredIcon {
        id: icon

        anchors.fill: parent
        source: Icons.getTrayIcon(root.modelData.id, root.modelData.icon)
        // m3tertiary, matching PillContainer's foreground: a recoloured tray
        // icon sits inline with the status glyphs, so a separate tone reads as
        // a mismatch rather than a rank. See the note in StatusIcons.qml.
        colour: Colours.palette.m3tertiary
        // Off by default (BarConfig.qml), which means the raw app pixmap is
        // drawn untouched — LocalSend, for one, ships literal `logo-32-white.png`
        // and lands at L≈99%, brighter than anything in the palette.
        layer.enabled: Config.bar.tray.recolour
    }
}
