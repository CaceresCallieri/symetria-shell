import qs.components
import qs.components.effects
import qs.services
import qs.config
import QtQuick

/// Active workspace indicator for the merged bar.
/// Duplicated from modules/bar/components/workspaces/ActiveIndicator.qml (Repeater mode only).
/// Items in `workspaces` Repeater must expose:
///   ws: int, x: real, indicatorSize: int, indicatorOffset: int
/// (isWorkspace is a marker for external consumers, not read by this component)
StyledRect {
    id: root

    property int activeWsId: -1
    property Repeater workspaces: null

    required property Item mask

    property color indicatorColor: Colours.palette.m3primary
    property color textColor: Colours.palette.m3onSurface

    readonly property var glassStyle: Colours.pillStyle(indicatorColor, Colours.glass.strong)

    readonly property int currentWsIdx: {
        if (!workspaces)
            return -1;
        for (let i = 0; i < workspaces.count; i++) {
            const item = workspaces.itemAt(i);
            if (item && item.ws === activeWsId)
                return i;
        }
        return -1;
    }

    readonly property var currentWs: currentWsIdx >= 0 ? workspaces.itemAt(currentWsIdx) : null

    visible: currentWs !== null

    readonly property real itemSize: currentWs?.indicatorSize ?? 0
    readonly property real itemOffset: currentWs?.indicatorOffset ?? 0

    property real leading: currentWs?.x ?? 0
    property real trailing: currentWs?.x ?? 0
    property real currentSize: itemSize
    property real indicatorOffset: itemOffset
    property real offset: Math.min(leading, trailing) - indicatorOffset
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        if (Config.bar.workspaces.activeTrail && previousWsIdx >= 0 && previousWsIdx > currentWsIdx) {
            const prevWs = workspaces?.itemAt(previousWsIdx);
            return prevWs ? Math.min(prevWs.x + prevWs.indicatorSize - offset, s) : s;
        }
        return s;
    }

    property int currentWsIdxTracked: -1
    property int previousWsIdx: -1

    onCurrentWsIdxChanged: {
        previousWsIdx = currentWsIdxTracked;
        currentWsIdxTracked = currentWsIdx;
    }

    clip: true
    x: offset + mask.x
    implicitHeight: Config.bar.sizes.indicatorHeight
    implicitWidth: size
    radius: Appearance.rounding.full
    color: glassStyle.background
    border.width: 1
    border.color: glassStyle.border

    Colouriser {
        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: root.textColor

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
        easing.bezierCurve: Appearance.anim.curves.standardDecel
    }
}
