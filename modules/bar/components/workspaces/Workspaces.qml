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

    // intentional var: JS object used as hash map ({ [wsId]: bool }).
    // Computation centralized in Hypr.occupiedMap() — shared with merged agentbar.
    readonly property var occupied: Hypr.occupiedMap()
    readonly property int groupOffset: Math.floor((activeWsId - 1) / Config.bar.workspaces.shown) * Config.bar.workspaces.shown

    // In fixed mode return a static [1..shown] window; otherwise delegate to the
    // shared Hypr.displayedWorkspaceIds() (special workspaces excluded — the top
    // bar handles them via SpecialWorkspaces.qml overlay, not inline slots).
    readonly property list<int> displayedWorkspaces: {
        if (!Config.bar.workspaces.showOnlyOccupied) {
            return Array.from({length: Config.bar.workspaces.shown}, (_, i) => groupOffset + i + 1)
        }
        return Hypr.displayedWorkspaceIds(false, root.activeWsId)
    }

    property real blur: onSpecial ? 1 : 0

    // Dot sizing
    readonly property int dotSize: 4
    readonly property int dotSpacing: Appearance.spacing.normal

    // FORM axis: this is the third bar-plate producer. It sizes and offsets
    // through the shared Theme contract so the panel form's off-screen bleed
    // reaches it too — see the CONTRACT note on barPlateHeight in
    // services/Theme.qml.
    readonly property int contentOffset: Theme.barPlateContentOffset

    implicitHeight: Theme.barPlateHeight
    implicitWidth: multiMonitor ? leftDot.width + dotSpacing + pill.implicitWidth + dotSpacing + rightDot.width : pill.implicitWidth

    // Focus indicator dot - left side
    Rectangle {
        id: leftDot
        anchors.right: pill.left
        anchors.rightMargin: root.dotSpacing
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.contentOffset
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

    // The workspace pill — uses the shared PillSurface for claymorphism styling.
    // Content is declared inside its default slot so full-bleed overlays
    // (OccupiedBg, ActiveIndicator, SpecialWorkspaces) are clipped to the
    // rounded capsule shape.
    PillSurface {
        id: pill

        anchors.centerIn: parent

        implicitHeight: Theme.barPlateHeight
        implicitWidth: layout.implicitWidth + Appearance.padding.large * 2

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
                // Centred on the VISIBLE band: the plate's top `barTopBleed` px
                // are off-screen under the panel form.
                anchors.verticalCenterOffset: root.contentOffset
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
        anchors.verticalCenterOffset: root.contentOffset
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
