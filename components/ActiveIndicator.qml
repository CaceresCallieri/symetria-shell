import qs.components
import qs.components.effects
import qs.services
import qs.config
import QtQuick

// Unified active workspace indicator supporting both Repeater and ListView modes.
// Shared by both the top bar workspace pill and the merged agentbar workspace strip.
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

    // MEASURED INERT — do not tune this expecting to see a result. A screen
    // capture of the merged bar with a workspace active shows the label over
    // this indicator rendering LIGHT, not in this dark m3onPrimary tint. Every
    // consumer puts the indicator in a Loader at `z: -1`, i.e. below its own
    // mask, and Colouriser is a MultiEffect that does not hide its source — so
    // the real workspace labels paint over the tinted copy and this never
    // reaches the screen.
    //
    // Left in place rather than deleted: it is part of the public API that
    // SpecialWorkspaces and MergedBarContent both set, and removing it (with
    // the Colouriser) is a separate change that deserves its own verification
    // pass rather than riding along with a colour tweak.
    property color textColor: Colours.palette.m3onPrimary

    // --- Pill styling (strong intensity for active indicator) ---
    // ENGAGED, but at the BROAD lift rather than the socket's `standard`.
    //
    // This is the widest engaged surface in the shell — a workspace pill with a
    // window title in it runs 300px+ — and area is the variable the small-control
    // presets do not account for. Measured on a capture at `standard`: body plus
    // polished finish composited to lightness 0.50 against a 0.09 bar plate, which
    // made the indicator the loudest thing on screen and washed out the very label
    // it sits behind. `broad` lands it near 0.30. See Colours.polish.
    readonly property var glassStyle: Colours.engagedPillStyle(indicatorColor, Colours.glass.strong, Colours.polish.broad) // intentional var: heterogeneous JS { background, border }

    // --- Mode detection ---
    readonly property bool useListView: listView !== null

    // When true (merged agent bar), the mask wraps onto multiple rows and the indicator must
    // track the active slot's row vertically. Default false → single-row consumers (top bar,
    // special workspaces, calendar) are byte-for-byte unaffected (rowYOffset stays 0 and the
    // colouriser keeps its original implicit sizing).
    property bool multiRow: false

    // Horizontal shift applied to the active row so the indicator tracks a centred (partial)
    // wrapped row's slots. Supplied by the merged-bar consumer to match the per-item Translate
    // that centres wrapped rows; 0 (and thus inert) for single-row consumers.
    property real rowXOffset: 0

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
    // intentional var: nullable polymorphic — Repeater item (workspace) or ListView.currentItem (special workspace)
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
    property real offset: Math.min(leading, trailing) - indicatorOffset + rowXOffset
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        // Handle activeTrail animation: extend indicator to cover previous workspace
        // (only applicable in Repeater mode - ListView mode doesn't support trail)
        if (!useListView && Config.bar.workspaces.activeTrail && previousWsIdx >= 0 && previousWsIdx > currentWsIdx) {
            const prevWs = workspaces?.itemAt(previousWsIdx);
            // In the merged multi-row bar, only trail across same-row neighbours — a cross-row
            // trail would compute a bogus horizontal span (item x is relative to its own row).
            // The !multiRow short-circuit keeps single-row consumers' behaviour byte-identical.
            if (prevWs && (!multiRow || prevWs.y === currentWs?.y))
                return Math.min(prevWs.x + prevWs.indicatorSize - offset, s);
            return s;
        }
        return s;
    }

    // Vertical offset of the active slot's row centre from the mask's overall centre. Drives
    // both the indicator box (via the consumer's Loader anchors.verticalCenterOffset, which reads
    // this back) and the colouriser's compensating shift. Zero on a single row, so it only does
    // anything once multiRow content has actually wrapped.
    property real rowYOffset: {
        if (!multiRow || useListView || !currentWs || !mask)
            return 0;
        return (currentWs.y + currentWs.height / 2) - (mask.height / 2);
    }

    // Track workspace index changes for trail animation
    property int currentWsIdxTracked: -1  // Committed snapshot of currentWsIdx — captures "previous" before next update
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
    // Neumorphic recipe: zero border so a drawn outline doesn't compete with
    // the gradient-defined depression edges, matching PillToggleSurface's
    // pressed-in look on the quick toggles. (border.color is omitted because
    // width is hard-zero here — unlike PillToggleSurface, this indicator
    // never animates the border up.)
    border.width: 0

    // Inset depression — shared with PillToggleSurface and the calendar's today
    // cell. These alphas used to be written here as literals (0.55 / 0.12 /
    // × 0.5), which are CLAY's numbers, so this indicator kept drawing clay's
    // depression after metal became the default material. Reading Theme.toggle
    // is what makes it follow `symmetria shell surface material <name>` like
    // everything else.
    // Rendered before the Colouriser so the icon glyph stays crisp.
    // `Theme.toggle` is BORROWED here, not owned: this indicator is not a
    // toggle, but it should feel like one, so it reads the toggle role's inset
    // numbers. The cost is that a material cannot give the active-workspace
    // marker a different depression from the quick toggles without splitting
    // them. Acceptable while they are meant to match; if that stops being true,
    // add an `inset` sub-block to each material's `engaged` recipe.
    //
    // `root.radius`, not `parent.radius` — correct here either way since the
    // root IS the rounded rect, but the parent-radius form is right in some
    // primitives and silently wrong in others (docs/qml-pitfalls.md), so the
    // codebase should not train it.
    InsetDepression {
        anchors.fill: parent
        radius: root.radius
        darkAlpha: Theme.toggle.darkInsetAlpha
        lightAlpha: Theme.toggle.lightInsetAlpha
        horizontalWeight: Theme.toggle.horizontalInsetWeight
    }

    // Polished finish. `specularFactor` is not defaulted away here the way
    // PillToggleSurface defaults it to zero for a pressed pill: this surface is
    // inset AND lit, which is the same call the connected socket makes. Without
    // it the indicator is a flat swatch with no highlight.
    SurfaceFinish {
        anchors.fill: parent
        radius: root.radius
        recipe: Theme.engaged
    }

    Colouriser {
        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: root.textColor

        x: -root.offset
        // Multi-row (merged bar): size to the mask's ACTUAL extent so the rendered texture maps
        // 1:1 (MultiEffect renders the source at its real size, not implicitWidth) and includes
        // every row; verticalCenterOffset then shifts the active row's band into the one-row-tall
        // indicator. Single-row consumers keep the original implicit sizing and a zero offset.
        implicitWidth: root.multiRow ? root.mask.width : root.mask.implicitWidth
        implicitHeight: root.multiRow ? root.mask.height : root.mask.implicitHeight

        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.rowYOffset
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

    // Vertical glide when the active slot switches rows (merged multi-row bar only).
    Behavior on rowYOffset {
        EAnim {}
    }

    component EAnim: Anim {
        easing.bezierCurve: Appearance.anim.curves.standardDecel
    }
}
