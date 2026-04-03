pragma ComponentBehavior: Bound

import qs.components
import qs.components.effects
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property string activeSpecial: (Config.bar.workspaces.perMonitorWorkspaces ? monitor : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace.name ?? ""

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: mask
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0)
                }
                GradientStop {
                    position: 0.3
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 0.7
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0)
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.bottom: parent.bottom

            radius: Appearance.rounding.full
            implicitWidth: parent.width / 2
            opacity: view.contentX > 0 ? 0 : 1

            Behavior on opacity {
                Anim {}
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            radius: Appearance.rounding.full
            implicitWidth: parent.width / 2
            opacity: view.contentX < view.contentWidth - parent.width + Appearance.padding.small ? 0 : 1

            Behavior on opacity {
                Anim {}
            }
        }
    }

    ListView {
        id: view

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: contentWidth > 0 && contentWidth < parent.width ? contentWidth : parent.width
        spacing: Appearance.spacing.normal
        interactive: false
        orientation: ListView.Horizontal

        currentIndex: model.values.findIndex(w => w.name === root.activeSpecial)
        onCurrentIndexChanged: currentIndex = Qt.binding(() => model.values.findIndex(w => w.name === root.activeSpecial))

        model: ScriptModel {
            values: Hypr.workspaces.values.filter(w => w.name.startsWith("special:") && (!Config.bar.workspaces.perMonitorWorkspaces || w.monitor === root.monitor))
        }

        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        highlightRangeMode: ListView.StrictlyEnforceRange

        highlightFollowsCurrentItem: false
        highlight: Item {
            x: view.currentItem?.x ?? 0
            implicitWidth: view.currentItem?.size ?? 0

            Behavior on x {
                Anim {}
            }
        }

        delegate: RowLayout {
            id: ws

            required property HyprlandWorkspace modelData
            readonly property bool isActive: ListView.isCurrentItem
            readonly property int size: content.totalWidth + (content.hasWindows ? Appearance.padding.small : 0)
            // Cached from modelData to survive delegate destruction during ListView remove animation
            property int wsId
            property string icon
            property bool hasWindows

            anchors.top: view.contentItem.top
            anchors.bottom: view.contentItem.bottom

            spacing: 0

            Component.onCompleted: {
                wsId = modelData.id;
                icon = Icons.getSpecialWsIcon(modelData.name);
                hasWindows = Config.bar.workspaces.showWindowsOnSpecialWorkspaces && modelData.lastIpcObject.windows > 0;
            }

            // Hacky thing cause modelData gets destroyed before the remove anim finishes
            Connections {
                target: ws.modelData

                function onIdChanged(): void {
                    if (ws.modelData)
                        ws.wsId = ws.modelData.id;
                }

                function onNameChanged(): void {
                    if (ws.modelData)
                        ws.icon = Icons.getSpecialWsIcon(ws.modelData.name);
                }

                function onLastIpcObjectChanged(): void {
                    if (ws.modelData)
                        ws.hasWindows = Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.modelData.lastIpcObject.windows > 0;
                }
            }

            Connections {
                target: Config.bar.workspaces

                function onShowWindowsOnSpecialWorkspacesChanged(): void {
                    if (ws.modelData)
                        ws.hasWindows = Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.modelData.lastIpcObject.windows > 0;
                }
            }

            WorkspaceContent {
                id: content

                wsId: ws.wsId
                icon: ws.icon
                hasWindows: ws.hasWindows && ws.isActive
            }
        }

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }

        remove: Transition {
            Anim {
                property: "scale"
                to: 0.5
                duration: Appearance.anim.durations.small
            }
            Anim {
                property: "opacity"
                to: 0
                duration: Appearance.anim.durations.small
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        displaced: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }
    }

    Loader {
        active: Config.bar.workspaces.activeIndicator
        asynchronous: true
        anchors.verticalCenter: parent.verticalCenter
        z: -1  // Render behind workspace content so icons aren't muted

        sourceComponent: ActiveIndicator {
            listView: view
            mask: view
            indicatorColor: Colours.palette.m3tertiary
            textColor: Colours.palette.m3onTertiary
        }
    }

    MouseArea {
        property real startX

        anchors.fill: view
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        drag.target: view.contentItem
        drag.axis: Drag.XAxis
        drag.maximumX: 0
        drag.minimumX: view.contentWidth > view.width
            ? view.width - view.contentWidth - Appearance.padding.small
            : 0

        onPressed: event => startX = event.x

        onClicked: event => {
            if (Math.abs(event.x - startX) > drag.threshold)
                return;

            const ws = view.itemAt(event.x, event.y);
            if (ws?.modelData)
                Hypr.dispatch(`togglespecialworkspace ${ws.modelData.name.slice(8)}`);
            else
                Hypr.dispatch("togglespecialworkspace special");
        }
    }
}
