pragma ComponentBehavior: Bound

import qs.services
import qs.config
import qs.components
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root

    required property ShellScreen screen

    readonly property bool onSpecial: (Config.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace.name !== ""
    readonly property int activeWsId: Config.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen)?.activeWorkspace?.id ?? 1) : Hypr.activeWsId

    // Monitor focus detection for indicator dots (hidden with single monitor)
    readonly property bool multiMonitor: Quickshell.screens.length > 1
    readonly property bool isMonitorFocused: multiMonitor && (Hypr.monitorFor(screen)?.focused ?? false)

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

    // Glassmorphism styling (matching other bar pills like Tray, TimePill, SystemPill)
    readonly property var glassStyle: Colours.pillStyle(
        Colours.palette.m3surfaceContainerHigh,
        Colours.glass.subtle
    )

    // Dot sizing
    readonly property int dotSize: 4
    readonly property int dotSpacing: Appearance.spacing.normal

    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: multiMonitor ? leftDot.width + dotSpacing + pill.implicitWidth + dotSpacing + rightDot.width : pill.implicitWidth

    // Focus indicator dot - left side
    Rectangle {
        id: leftDot
        anchors.right: pill.left
        anchors.rightMargin: root.dotSpacing
        anchors.verticalCenter: parent.verticalCenter
        visible: root.multiMonitor
        width: root.dotSize
        height: root.dotSize
        radius: root.dotSize / 2
        color: Colours.palette.m3primary
        opacity: root.isMonitorFocused ? 1 : 0

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.normal
            }
        }
    }

    // The workspace pill
    StyledClippingRect {
        id: pill

        anchors.centerIn: parent

        implicitHeight: Config.bar.sizes.innerWidth
        implicitWidth: layout.implicitWidth + Appearance.padding.large * 2

        color: root.glassStyle.background
        radius: Appearance.rounding.full
        border.width: 1
        border.color: root.glassStyle.border

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
                z: -1  // Render behind workspace content so icons aren't muted

                sourceComponent: ActiveIndicator {
                    activeWsId: root.activeWsId
                    workspaces: workspaces
                    mask: layout
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
    }

    // Focus indicator dot - right side
    Rectangle {
        id: rightDot
        anchors.left: pill.right
        anchors.leftMargin: root.dotSpacing
        anchors.verticalCenter: parent.verticalCenter
        visible: root.multiMonitor
        width: root.dotSize
        height: root.dotSize
        radius: root.dotSize / 2
        color: Colours.palette.m3primary
        opacity: root.isMonitorFocused ? 1 : 0

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.normal
            }
        }
    }

    Behavior on blur {
        Anim {
            duration: Appearance.anim.durations.small
        }
    }
}
