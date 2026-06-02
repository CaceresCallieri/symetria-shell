pragma ComponentBehavior: Bound

import qs.config
import QtQuick

/// OpenCode activity indicator: a 3×3 grid of small squares.
///
/// Visual identity counterpart to ClaudeSparkle — where Claude shows a
/// hand-drawn starburst sparkle, OpenCode shows a blocky grid. This mirrors
/// OpenCode's own TUI loading indicator (a bright "comet" head sweeping across
/// cells, leaving an exponentially-fading tail).
///
/// - busy:  a comet sweeps a serpentine (boustrophedon) path across ALL nine
///          cells — top row left→right, middle row right→left, bottom row
///          left→right — then reverses back along the same path, ping-ponging
///          end to end so every square (the center included) lights up. Each
///          cell's opacity = idle + (1-idle)·falloff^(distance BEHIND the head
///          along the current travel direction), so the head is full-bright
///          with a fading tail and a sharp leading edge.
/// - idle:  the grid fades out entirely, collapsing to a single dim center
///          square — the blocky analogue of Claude's dormant dot.
///
/// Only color/opacity changes — no hue shift along the tail — matching the
/// source animation. Cells are square (radius 0) by design; that squareness
/// is the whole point of the differentiation.
Item {
    id: root

    /// Per-backend accent (OpenCode azure). Driven by AgentChip._accentColor.
    required property color color
    /// True while the agent is working/thinking — runs the sweeping comet.
    /// When false, the grid collapses to the single idle center square.
    property bool busy: false

    // Match ClaudeSparkle's footprint so the two are interchangeable inside
    // AgentChip without disturbing layout (~1.4× font cap-height).
    readonly property real _size: Appearance.font.size.small * 1.4
    implicitWidth: _size
    implicitHeight: _size

    // --- Grid geometry ---
    readonly property real _gap: _size * 0.14
    readonly property real _cell: (_size - 2 * _gap) / 3

    // --- Comet tuning (all tweakable; defaults derived from the OpenCode TUI) ---
    // One-way sweep across the 9-cell serpentine (8 cell-to-cell steps). 1280ms
    // = 160ms/cell, 20% faster than the prior 200ms/cell perimeter comet. A full
    // ping-pong (out-and-back) therefore takes sweepMs × 2.
    property int sweepMs: 1280
    property real _falloff: 0.55           // brightness ratio per cell behind the head
    property real _idleBrightness: 0.22    // dim floor for cells while busy
    property real _centerIdleOpacity: 0.70 // the lone "little square" when idle

    // Maps a row-major grid index (0..8) to its position along the serpentine
    // path (0..8). The path snakes through every cell — no center exception.
    //   0 1 2      path: TL(0) TC(1) TR(2) MR(3) MC(4) ML(5) BL(6) BC(7) BR(8)
    //   3 4 5      i.e. grid 0,1,2,5,4,3,6,7,8 — top L→R, middle R→L, bottom L→R.
    //   6 7 8
    readonly property list<int> _pathIndex: [0, 1, 2, 5, 4, 3, 6, 7, 8]

    // Single linear phase 0→2 drives the ping-pong: 0→1 is the forward sweep,
    // 1→2 the return. Head position (triangle wave) and travel direction are
    // both derived from it, so there's one animation and no segment to sync.
    property real _phase: 0
    NumberAnimation on _phase {
        running: root.busy && root.visible
        loops: Animation.Infinite
        from: 0
        to: 2
        duration: root.sweepMs * 2
        easing.type: Easing.Linear
    }

    // Robotic cadence — snap the continuous phase to a low frame rate so the comet
    // *ticks* cell-to-cell like a machine scan instead of gliding. This is the
    // OpenCode personality: mechanical, where Claude's 60fps sparkle is soft. The
    // animation still runs at 60fps; we read a floored copy so each frame holds
    // until the next boundary (true stop-motion). steps derived from robotFps so
    // the tick rate stays stable if sweepMs is retuned.
    property int robotFps: 10
    readonly property int _steps: Math.max(2, Math.round(root.sweepMs * 2 / 1000 * root.robotFps))
    readonly property real _qPhase: Math.floor(root._phase / 2 * root._steps) / root._steps * 2

    // Quantized head position along the 9-cell path (0..8), bouncing at each end.
    readonly property real _cometPos: _qPhase <= 1 ? _qPhase * 8 : (2 - _qPhase) * 8
    // +1 while sweeping forward (0→8), -1 while returning (8→0).
    readonly property int _dir: _qPhase <= 1 ? 1 : -1

    // Fade the whole grid in/out as busy toggles. Behavior lives HERE (on a
    // single property), NOT on each cell's opacity — a Behavior on cell.opacity
    // would smear the per-frame comet brightness. Multiplying by this fade keeps
    // the comet instantaneous while the reveal/collapse animates smoothly.
    property real _gridFade: root.busy ? 1.0 : 0.0
    Behavior on _gridFade {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    /// Instantaneous comet brightness for a cell (no Behavior — read every frame
    /// as the head advances). Distance is measured BEHIND the head along the
    /// current travel direction so the tail trails behind it; cells AHEAD of the
    /// head drop to the idle floor, giving the comet a sharp leading edge.
    function _cometBrightness(gridIndex: int): real {
        const pos = root._pathIndex[gridIndex];
        const behind = root._dir > 0 ? (root._cometPos - pos) : (pos - root._cometPos);
        if (behind < 0)
            return root._idleBrightness;
        return root._idleBrightness + (1 - root._idleBrightness) * Math.pow(root._falloff, behind);
    }

    Grid {
        anchors.centerIn: parent
        rows: 3
        columns: 3
        rowSpacing: root._gap
        columnSpacing: root._gap

        Repeater {
            model: 9

            Rectangle {
                required property int index

                width: root._cell
                height: root._cell
                radius: 0 // square by design — the blocky look IS the differentiation
                color: root.color
                // Busy: every cell follows the sweeping comet (gated by the grid
                // fade). Idle: the grid fades to nothing except the center square,
                // which crossfades up to its lone-indicator opacity. The two terms
                // are blended by _gridFade so busy↔idle transitions stay smooth.
                opacity: root._gridFade * root._cometBrightness(index)
                    + (1 - root._gridFade) * (index === 4 ? root._centerIdleOpacity : 0)
            }
        }
    }
}
