pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    required property int wsId
    required property string icon
    required property bool hasWindows

    // Optional customization
    property color labelColor: Colours.palette.m3onSurface
    property bool animateLabel: false
    property real windowsLeftMargin: 0
    property bool animateWindowsWidth: true

    // Read-only for external size calculations
    readonly property int labelWidth: label.Layout.preferredWidth
    readonly property int windowsWidth: windows.active ? windows.implicitWidth : 0
    readonly property int totalWidth: labelWidth + windowsWidth

    spacing: 0

    Loader {
        id: label

        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
        Layout.preferredWidth: Config.bar.sizes.indicatorHeight

        // intentional var: JS object { useMaterial: bool, iconText: string } from Icons.parseIcon()
        readonly property var parsedIcon: Icons.parseIcon(root.icon)
        readonly property bool useMaterialIcon: parsedIcon.useMaterial
        readonly property string iconText: parsedIcon.iconText

        sourceComponent: useMaterialIcon ? iconComp : letterComp

        Component {
            id: iconComp

            MaterialIcon {
                fill: 1
                text: label.iconText
                color: root.labelColor
                horizontalAlignment: Qt.AlignHCenter
            }
        }

        Component {
            id: letterComp

            StyledText {
                animate: root.animateLabel
                text: label.iconText
                color: root.labelColor
                horizontalAlignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        id: windows

        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: true
        Layout.preferredWidth: implicitWidth
        Layout.leftMargin: root.windowsLeftMargin

        visible: active
        active: root.hasWindows
        asynchronous: true

        sourceComponent: WorkspaceAppIcons {
            workspaceId: root.wsId
        }

        Behavior on Layout.preferredWidth {
            enabled: root.animateWindowsWidth
            Anim {}
        }
    }
}
