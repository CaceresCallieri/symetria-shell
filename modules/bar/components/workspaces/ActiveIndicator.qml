import qs.components
import qs.components.effects
import qs.services
import qs.config
import QtQuick

StyledRect {
    id: root

    required property int activeWsId
    required property Repeater workspaces
    required property Item mask

    readonly property int currentWsIdx: {
        // Find the index of the active workspace in the repeater
        for (let i = 0; i < workspaces.count; i++) {
            const item = workspaces.itemAt(i)
            if (item && item.ws === activeWsId) {
                return i
            }
        }
        return -1  // Not found - indicator will be hidden
    }

    visible: currentWsIdx >= 0

    // Cache the current workspace item to avoid repeated lookups
    readonly property var currentWs: currentWsIdx >= 0 ? workspaces.itemAt(currentWsIdx) : null

    property real leading: currentWs?.x ?? 0
    property real trailing: currentWs?.x ?? 0
    property real currentSize: currentWs?.indicatorSize ?? 0
    property real indicatorOffset: currentWs?.indicatorOffset ?? 0
    property real offset: Math.min(leading, trailing) - indicatorOffset
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        // Handle activeTrail animation: extend indicator to cover previous workspace
        if (Config.bar.workspaces.activeTrail &&
            previousWsIdx !== undefined &&
            previousWsIdx >= 0 &&
            previousWsIdx > currentWsIdx) {
            const prevWs = workspaces.itemAt(previousWsIdx);
            return prevWs ? Math.min(prevWs.x + prevWs.indicatorSize - offset, s) : s;
        }
        return s;
    }

    // Track workspace index changes for trail animation
    property int currentWsIdxTracked: -1  // Current workspace index being tracked
    property int previousWsIdx: -1        // Previous workspace for trail animation

    onCurrentWsIdxChanged: {
        previousWsIdx = currentWsIdxTracked;
        currentWsIdxTracked = currentWsIdx;
    }

    clip: true
    x: offset + mask.x
    implicitHeight: Config.bar.sizes.innerWidth - Appearance.padding.small * 2
    implicitWidth: size
    radius: Appearance.rounding.full
    color: Colours.palette.m3primary

    Colouriser {
        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: Colours.palette.m3onPrimary

        x: -root.offset
        y: 0
        implicitWidth: root.mask.implicitWidth
        implicitHeight: root.mask.implicitHeight

        anchors.verticalCenter: parent.verticalCenter
    }

    Behavior on leading {
        enabled: Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on trailing {
        enabled: Config.bar.workspaces.activeTrail

        EAnim {
            duration: Appearance.anim.durations.normal * 2
        }
    }

    Behavior on currentSize {
        enabled: Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on offset {
        enabled: !Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on size {
        enabled: !Config.bar.workspaces.activeTrail

        EAnim {}
    }

    component EAnim: Anim {
        easing.bezierCurve: Appearance.anim.curves.emphasized
    }
}
