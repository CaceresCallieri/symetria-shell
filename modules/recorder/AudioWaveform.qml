pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Reusable audio waveform visualization for recording sessions.
///
/// Renders animated vertical bars that respond to live audio level
/// during recording, show a sine wave pattern during processing,
/// and dim to gold during pause. Used by both the drawer Content
/// and the bar-embedded RecordingBarEmbed.
Item {
    id: root

    /// Live audio RMS level (0.0–1.0) from job.audioLevel.
    property real audioLevel: 0

    /// Current recording state: "recording", "paused", "processing".
    property string displayState: "recording"

    /// Number of visualizer bars.
    property int barCount: 16

    /// Height of the bar container in pixels.
    property int containerHeight: 24

    /// Controls whether the animation loop runs.
    property bool active: true

    implicitWidth: barRow.implicitWidth
    implicitHeight: containerHeight

    // ── Audio visualization tuning ──────────────────────────────
    readonly property QtObject audioConfig: QtObject {
        readonly property real noiseFloor: 0.025  // just below ambient (~0.03), silence ≈ 0
        readonly property real gain: 15.0         // clips at ~0.09 RMS (speech ceiling)
        readonly property real powerCurve: 0.5    // sqrt curve: boosts mids
        readonly property real waveVariation: 0.30
        readonly property real waveSpeed: 0.08
        readonly property real waveFrequency: 0.8
        readonly property real minBarHeight: 2
        readonly property real maxBarHeight: 20
        readonly property real smoothingFactor: 0.25  // per-frame decay at 60fps (framerate-independent via FrameAnimation.frameTime)
    }

    // Paused state visual configuration
    readonly property color pausedBarColor: "#C9B458"
    readonly property real pausedDimOpacity: 0.55

    // Processing wave effect configuration
    readonly property QtObject processingConfig: QtObject {
        readonly property real waveSpeed: 0.12
        readonly property real baseHeightBoost: 0.70
        readonly property real harmonicStrength: 0.12
        readonly property real opacityMin: 0.75
        readonly property real opacityRange: 0.25
    }

    // ── Animation time for bar oscillation ──────────────────────
    property real animationTime: 0

    NumberAnimation on animationTime {
        running: (root.displayState === "recording" || root.displayState === "processing") && root.active
        from: 0
        to: 6000
        duration: 100000
        loops: Animation.Infinite
    }

    // ── Cached bar gradient colors ──────────────────────────────
    property list<color> barColors: []

    function updateBarColors(): void {
        const colors = [];
        for (let i = 0; i < barCount; i++) {
            const t = i / barCount;
            colors.push(Qt.tint(Colours.palette.m3primary,
                Qt.rgba(Colours.palette.m3tertiary.r,
                        Colours.palette.m3tertiary.g,
                        Colours.palette.m3tertiary.b,
                        t * 0.5)));
        }
        barColors = colors;
    }

    Component.onCompleted: updateBarColors()

    Connections {
        target: Colours.palette
        function onM3primaryChanged() { root.updateBarColors(); }
        function onM3tertiaryChanged() { root.updateBarColors(); }
    }

    // ── Pre-calculated wave offsets (recording mode) ────────────
    readonly property var waveOffsets: {
        if (root.displayState !== "recording" || !root.active) return [];
        const cfg = audioConfig;
        const offsets = [];
        for (let i = 0; i < barCount; i++) {
            const baseline = 1 - cfg.waveVariation;
            offsets.push(Math.sin(i * cfg.waveFrequency + animationTime * cfg.waveSpeed) * cfg.waveVariation + baseline);
        }
        return offsets;
    }

    // ── Processing wave data (offsets + opacities) ──────────────
    readonly property var processingWaveData: {
        if (root.displayState !== "processing" || !root.active) return { offsets: [], opacities: [] };
        const cfg = processingConfig;
        const offsets = [];
        const opacities = [];
        for (let i = 0; i < barCount; i++) {
            const spatialPhase = (i / (barCount - 1)) * 2 * Math.PI;
            const wavePos = spatialPhase - animationTime * cfg.waveSpeed;
            const primaryWave = 0.5 + 0.5 * Math.sin(wavePos);
            const harmonic = cfg.harmonicStrength * Math.sin(wavePos * 2);
            offsets.push(Math.max(0, primaryWave + harmonic));
            opacities.push(cfg.opacityMin + cfg.opacityRange * primaryWave);
        }
        return { offsets, opacities };
    }

    readonly property list<real> processingWaveOffsets: processingWaveData.offsets ?? []
    readonly property list<real> processingWaveOpacities: processingWaveData.opacities ?? []

    // ── Bar visualization ───────────────────────────────────────
    Row {
        id: barRow

        anchors.centerIn: parent
        spacing: 3

        Repeater {
            model: root.barCount

            Rectangle {
                id: bar

                required property int index

                readonly property real positionFactor: {
                    const center = root.barCount / 2;
                    const distance = Math.abs(index - center) / center;
                    return 1 - distance * 0.5;
                }

                readonly property real targetHeight: {
                    const cfg = root.audioConfig;

                    if (root.displayState === "processing") {
                        const procCfg = root.processingConfig;
                        const waveMultiplier = root.processingWaveOffsets[index] ?? 1.0;
                        const boostedHeight = procCfg.baseHeightBoost * (cfg.maxBarHeight - cfg.minBarHeight);
                        const rawHeight = cfg.minBarHeight + boostedHeight * waveMultiplier * positionFactor;
                        return Math.max(cfg.minBarHeight, Math.min(cfg.maxBarHeight, rawHeight));
                    }

                    const rawLevel = root.audioLevel;
                    let effectiveLevel = 0;
                    if (rawLevel > cfg.noiseFloor) {
                        effectiveLevel = (rawLevel - cfg.noiseFloor) / (1.0 - cfg.noiseFloor);
                        effectiveLevel = Math.min(1.0, effectiveLevel * cfg.gain);
                        effectiveLevel = Math.pow(effectiveLevel, cfg.powerCurve);
                    }

                    const waveOffset = root.waveOffsets[index] ?? 1.0;
                    return cfg.minBarHeight + effectiveLevel * (cfg.maxBarHeight - cfg.minBarHeight) * positionFactor * waveOffset;
                }

                readonly property real waveOpacity: {
                    if (root.displayState === "processing") {
                        const opacity = root.processingWaveOpacities[index];
                        if (opacity !== undefined) return opacity;
                    }
                    if (root.displayState === "paused")
                        return root.pausedDimOpacity;
                    return 1.0;
                }

                property real smoothedHeight: targetHeight  // start at target to avoid snap-from-zero on first render

                // Continuous smoothing: lerp toward targetHeight every frame.
                // audioLevel arrives at ~10Hz; this fills the gaps at render
                // framerate so bars glide instead of snapping.
                //
                // DO NOT replace with Behavior on height { NumberAnimation }.
                // targetHeight changes every frame (via animationTime in waveOffsets),
                // which restarts the Behavior animation each frame — bars freeze
                // because the animation never progresses past its first 16ms.
                // DO NOT replace with onTargetHeightChanged imperative lerp.
                // That only fires on data arrival (~10Hz), leaving 90ms static
                // gaps between updates — bars snap instead of gliding.
                FrameAnimation {
                    running: root.active && root.displayState !== "paused"
                    onTriggered: {
                        const delta = bar.targetHeight - bar.smoothedHeight;
                        if (Math.abs(delta) > 0.1)
                            bar.smoothedHeight += delta * (1 - Math.pow(1 - root.audioConfig.smoothingFactor, frameTime * 60));
                        else
                            bar.smoothedHeight = bar.targetHeight;
                    }
                }

                width: 4
                height: smoothedHeight
                anchors.verticalCenter: parent?.verticalCenter ?? undefined

                radius: 2
                color: root.displayState === "paused" ? root.pausedBarColor : (root.barColors[index] ?? Colours.palette.m3primary)
                opacity: waveOpacity
            }
        }
    }
}
