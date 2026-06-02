pragma ComponentBehavior: Bound

import qs.config
import QtQuick

/// OpenCode STT soundwave: five square vertical bars in the backend accent.
///
/// Reuses the MOTION of ClaudeSparkle's STT soundwave (the stt-wave / stt-transcribe
/// sprites — a 5-bar wave, center tallest) but renders it as continuous-height
/// SQUARE bars (radius 0) instead of the sprites' rounded capsules, and in the
/// OpenCode azure rather than Claude orange. Same visual language as Claude's
/// recording indicator, distinct identity.
///
/// - recording (transcribing = false): center-pulse — the bars breathe with an
///   outward ripple, the center bar reaching highest (mirrors stt-wave's
///   center-pulse). This is the "listening" state.
/// - transcribing (transcribing = true): a tall bar travels left→right across the
///   row, wrapping (mirrors stt-transcribe's traveling wave). This is the
///   "processing the captured audio" state.
///
/// Shown by AgentChip only while the OpenCode agent is the STT target; the 3×3
/// OpenCodeGrid handles busy/idle. AgentChip cross-fades between the two.
Item {
    id: root

    /// Per-backend accent (OpenCode azure). Driven by AgentChip._accentColor.
    required property color color
    /// False = recording (center-pulse), true = transcribing (left→right travel).
    property bool transcribing: false

    // Match ClaudeSparkle / OpenCodeGrid footprint so the three are interchangeable
    // inside AgentChip without disturbing layout (~1.4× font cap-height).
    readonly property real _size: Appearance.font.size.small * 1.4
    implicitWidth: _size
    implicitHeight: _size

    // --- Bar geometry ---
    // Bar count is the main "blockiness" knob: fewer bars → wider, squarer bars →
    // more robotic. Width and gap DERIVE from it (bars always fill _barFill of the
    // footprint, gaps the rest), so dropping the count auto-widens each bar with
    // no manual retuning.
    property int _barCount: 4
    readonly property real _barFill: 0.66   // fraction of the width occupied by bars (rest is gaps)
    readonly property real _barWidth: _size * _barFill / _barCount
    readonly property real _gap: _barCount > 1 ? _size * (1 - _barFill) / (_barCount - 1) : 0
    readonly property real _minH: _size * 0.18   // square nub at rest (never zero — stays a block)
    readonly property real _maxH: _size * 0.9    // tallest a bar reaches

    // Index of the (possibly fractional) center bar, for the symmetric profile.
    readonly property real _center: (_barCount - 1) / 2

    /// Resting height weight for bar `i` — 1.0 at the center, falling to _edgeWeight
    /// at the outermost bars (center-dominant "voice" profile). Generalizes the old
    /// fixed [0.32, 0.62, 1.0, 0.62, 0.32] array to any _barCount.
    readonly property real _edgeWeight: 0.32
    function _barWeight(i: int): real {
        if (root._center <= 0) return 1.0;
        const t = Math.abs(i - root._center) / root._center; // 0 at center → 1 at edge
        return 1.0 - (1.0 - root._edgeWeight) * Math.pow(t, 1.5);
    }

    // --- Tuning ---
    property int recordingMs: 1000   // one full center-pulse breath
    property int transcribeMs: 1150  // one full left→right pass

    // Single looping phase drives both patterns; period depends on the sub-mode.
    property real _phase: 0
    NumberAnimation on _phase {
        running: root.visible
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: root.transcribing ? root.transcribeMs : root.recordingMs
        easing.type: Easing.Linear
    }

    // Robotic cadence — same mechanism as OpenCodeGrid: floor the phase to a low
    // frame rate so the bars tick between discrete heights instead of flowing,
    // giving OpenCode's STT a mechanical feel against Claude's smooth soundwave.
    property int robotFps: 10
    readonly property int _steps: Math.max(2, Math.round((root.transcribing ? root.transcribeMs : root.recordingMs) / 1000 * root.robotFps))
    readonly property real _qPhase: Math.floor(root._phase * root._steps) / root._steps

    /// Height of bar `i` (0..4) at the current (quantized) phase.
    function _barHeight(i: int): real {
        if (root.transcribing) {
            // Traveling bump: a tall bar at the sweep head, sharp falloff to the
            // sides, wrapping across the row left→right.
            const sweep = root._qPhase * root._barCount; // 0.._barCount
            let d = Math.abs(i - sweep);
            d = Math.min(d, root._barCount - d);         // wrap distance (seamless loop)
            const bump = Math.exp(-(d * d) / 0.8);
            return root._minH + (root._maxH - root._minH) * bump;
        }
        // Center-pulse: amplitude breathes, phase ripples outward from the center
        // bar so the wave reads as radiating rather than rising in unison.
        const dist = Math.abs(i - root._center);
        const pulse = 0.5 + 0.5 * Math.sin(2 * Math.PI * root._qPhase - dist * 1.1);
        return root._minH + (root._maxH - root._minH) * root._barWeight(i) * pulse;
    }

    Repeater {
        model: root._barCount

        Rectangle {
            required property int index

            width: root._barWidth
            height: root._barHeight(index)
            x: index * (root._barWidth + root._gap)
            anchors.verticalCenter: parent.verticalCenter // bars grow symmetrically about the midline
            radius: 0 // square bars — the whole point of the rework
            color: root.color
        }
    }
}
