import qs.components
import qs.components.effects
import qs.services
import qs.config
import QtQuick

// Unified active workspace indicator supporting both Repeater and ListView modes.
// - Repeater mode: Used by numbered/named workspaces (searches by activeWsId)
//   Item requirements: ws, x, indicatorSize, indicatorOffset
// - ListView mode: Used by special workspaces (uses currentItem directly)
//   Item requirements: x, size
StyledRect {
    id: root

    // --- Repeater mode properties (for numbered/named workspaces) ---
    property int activeWsId: -1
    property Repeater workspaces: null

    // --- ListView mode properties (for special workspaces) ---
    property ListView listView: null

    // --- Common required property ---
    required property Item mask

    // --- Color customization (special workspaces use tertiary colors) ---
    property color indicatorColor: Colours.palette.m3primary
    property color textColor: Colours.palette.m3onPrimary

    // --- Glassmorphism styling (strong intensity for active indicator) ---
    readonly property var glassStyle: Colours.glassmorphism(indicatorColor, Colours.glass.strong)

    // --- Mode detection ---
    readonly property bool useListView: listView !== null

    // --- Repeater mode: find active workspace index ---
    readonly property int currentWsIdx: {
        if (useListView)
            return -1;
        if (!workspaces)
            return -1;
        for (let i = 0; i < workspaces.count; i++) {
            const item = workspaces.itemAt(i);
            if (item && item.ws === activeWsId) {
                return i;
            }
        }
        return -1;  // Not found - indicator will be hidden
    }

    // --- Unified current item access ---
    readonly property var currentWs: {
        if (useListView)
            return listView?.currentItem ?? null;
        return currentWsIdx >= 0 ? workspaces.itemAt(currentWsIdx) : null;
    }

    visible: currentWs !== null

    // --- Position and size properties ---
    // For ListView mode, account for scroll offset (contentX)
    readonly property real contentOffset: useListView ? (listView?.contentX ?? 0) : 0
    // Item size: Repeater uses indicatorSize, ListView uses size
    readonly property real itemSize: currentWs?.indicatorSize ?? currentWs?.size ?? 0
    // Item offset: only Repeater mode has indicatorOffset (active padding)
    readonly property real itemOffset: currentWs?.indicatorOffset ?? 0

    property real leading: (currentWs?.x ?? 0) - contentOffset
    property real trailing: (currentWs?.x ?? 0) - contentOffset
    property real currentSize: itemSize
    property real indicatorOffset: itemOffset
    property real offset: Math.min(leading, trailing) - indicatorOffset
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        // Handle activeTrail animation: extend indicator to cover previous workspace
        // (only applicable in Repeater mode - ListView mode doesn't support trail)
        if (!useListView && Config.bar.workspaces.activeTrail && previousWsIdx !== undefined && previousWsIdx >= 0 && previousWsIdx > currentWsIdx) {
            const prevWs = workspaces?.itemAt(previousWsIdx);
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
        enabled: !useListView && Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on trailing {
        enabled: !useListView && Config.bar.workspaces.activeTrail

        EAnim {
            duration: Appearance.anim.durations.normal * 2
        }
    }

    Behavior on currentSize {
        enabled: !useListView && Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on offset {
        // ListView mode always uses standard animation (no trail support)
        enabled: useListView || !Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on size {
        // ListView mode always uses standard animation (no trail support)
        enabled: useListView || !Config.bar.workspaces.activeTrail

        EAnim {}
    }

    component EAnim: Anim {
        easing.bezierCurve: Appearance.anim.curves.emphasized
    }
}
