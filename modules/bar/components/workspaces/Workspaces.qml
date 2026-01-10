pragma ComponentBehavior: Bound

import qs.services
import qs.config
import qs.components
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

StyledClippingRect {
    id: root

    required property ShellScreen screen

    readonly property bool onSpecial: (Config.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace.name !== ""
    readonly property int activeWsId: Config.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId

    readonly property var occupied: Hypr.workspaces.values.reduce((acc, curr) => {
        acc[curr.id] = curr.lastIpcObject.windows > 0;
        return acc;
    }, {})
    readonly property int groupOffset: Math.floor((activeWsId - 1) / Config.bar.workspaces.shown) * Config.bar.workspaces.shown

    readonly property var displayedWorkspaces: {
        if (!Config.bar.workspaces.showOnlyOccupied) {
            // Legacy fixed mode - return array [1, 2, ..., shown]
            return Array.from({length: Config.bar.workspaces.shown}, (_, i) => groupOffset + i + 1)
        }

        // Dynamic mode - occupied + active + named workspaces
        // Exclude special workspaces (name starts with "special:") but keep named workspaces (which also have negative IDs)
        const validWorkspaces = Hypr.workspaces.values.filter(w => !w.name.startsWith("special:"))
        const occupiedWs = validWorkspaces.filter(w => w.lastIpcObject.windows > 0)
        const activeId = root.activeWsId

        // Get configured named workspace names
        const namedWsNames = Config.bar.workspaces.namedWorkspaceIcons.map(n => n.name)

        // Find named workspaces (always show these even if empty)
        const namedWs = validWorkspaces.filter(w => namedWsNames.includes(w.name))

        // Collect workspace IDs: occupied + named
        let ids = [...new Set([...occupiedWs.map(w => w.id), ...namedWs.map(w => w.id)])]

        // Ensure active workspace is included even if empty
        if (!ids.includes(activeId)) {
            ids.push(activeId)
        }

        // Sort ascending: negative IDs (named workspaces) first, then positive IDs
        return ids.sort((a, b) => a - b)
    }

    property real blur: onSpecial ? 1 : 0

    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: layout.implicitWidth + Appearance.padding.small * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Appearance.rounding.full

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Loader {
            // OccupiedBg is only relevant in fixed mode - in dynamic mode all visible workspaces are occupied/active
            active: Config.bar.workspaces.occupiedBg && !Config.bar.workspaces.showOnlyOccupied
            asynchronous: true

            anchors.fill: parent
            anchors.margins: Appearance.padding.small

            sourceComponent: OccupiedBg {
                workspaces: workspaces
                occupied: root.occupied
                groupOffset: root.groupOffset
            }
        }

        RowLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Math.floor(Appearance.spacing.small / 2)

            Repeater {
                id: workspaces

                model: ScriptModel {
                    values: root.displayedWorkspaces
                }

                Workspace {
                    required property int modelData

                    wsId: modelData
                    activeWsId: root.activeWsId
                    occupied: root.occupied
                }
            }
        }

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: Config.bar.workspaces.activeIndicator
            asynchronous: true

            sourceComponent: ActiveIndicator {
                activeWsId: root.activeWsId
                workspaces: workspaces
                mask: layout
            }
        }

        MouseArea {
            anchors.fill: layout
            onClicked: event => {
                const child = layout.childAt(event.x, event.y);
                if (!child || !child.isWorkspace) return;
                const wsId = child.ws;
                if (Hypr.activeWsId !== wsId) {
                    // Named workspaces (negative IDs) need "workspace name:<name>" syntax
                    if (wsId < 0) {
                        const wsObj = Hypr.workspaces.values.find(w => w.id === wsId);
                        if (wsObj) Hypr.dispatch(`workspace name:${wsObj.name}`);
                    } else {
                        Hypr.dispatch(`workspace ${wsId}`);
                    }
                } else {
                    Hypr.dispatch("togglespecialworkspace special");
                }
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {}
        }
    }

    Loader {
        id: specialWs

        anchors.fill: parent
        anchors.margins: Appearance.padding.small

        active: opacity > 0
        asynchronous: true

        scale: root.onSpecial ? 1 : 0.5
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: SpecialWorkspaces {
            screen: root.screen
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {}
        }
    }

    Behavior on blur {
        Anim {
            duration: Appearance.anim.durations.small
        }
    }
}
