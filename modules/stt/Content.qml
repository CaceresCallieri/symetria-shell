pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Content UI for a single SttJob in the speech-to-text drawer.
///
/// Displays state-based UI:
/// - recording: Animated audio level bars + elapsed time
/// - paused: Static audio level bars with pause icon + elapsed time
/// - processing: Flowing wave animation across bars (matches GTK implementation)
/// - error: Error icon + hint text
/// - success: Checkmark, brief display before auto-hide
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property SttService.SttJob job

    // Aliases so all existing internal references keep working without rename.
    // "transcribed" and "delivering" display as "processing" to the user.
    readonly property string serviceState: {
        const s = job.state;
        if (s === "transcribed" || s === "delivering") return "processing";
        return s;
    }
    readonly property real serviceAudioLevel: job.audioLevel
    readonly property real serviceElapsedSeconds: job.elapsedSeconds
    readonly property string serviceLanguage: job.language
    readonly property string serviceErrorDetail: job.errorDetail
    readonly property string serviceErrorHint: job.errorHint
    readonly property string serviceErrorRaw: job.errorRaw
    readonly property string serviceErrorSource: job.errorSource
    readonly property bool serviceIsAskMode: SttService.isAskMode
    readonly property string serviceDeliveryChoice: job.activeDeliveryChoice
    readonly property string serviceInjectionPath: job.injectionPath
    readonly property bool serviceInjectionDowngraded: job.injectionDowngraded
    readonly property bool serviceInjectionSubmitted: job.injectionSubmitted

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Number of audio visualizer bars
    readonly property int barCount: 20
    // Minimum drawer width for readability
    readonly property int minDrawerWidth: 300
    // Height of audio level bar container
    readonly property int audioBarContainerHeight: 48

    // Audio visualization tuning constants
    // Tuned for natural speech visualization. Adjust if bars feel laggy/jittery.
    readonly property QtObject audioConfig: QtObject {
        readonly property real smoothing: 0.35       // 0.2=laggy, 0.5=jittery, 0.35=balanced
        readonly property real noiseFloor: 0.025     // Just below ambient (~0.03), so silence ≈ 0
        readonly property real gain: 15.0            // Clips at ~0.09 RMS (speech ceiling). Recalculate if noiseFloor changes
        readonly property real powerCurve: 0.5       // Square root curve: boosts mids further
        readonly property real waveVariation: 0.30   // ±30% creates motion without chaos
        readonly property real waveSpeed: 0.08       // Gentle oscillation speed
        readonly property real waveFrequency: 0.8    // Wave pattern across bar array
        readonly property real minBarHeight: 2
        readonly property real maxBarHeight: 44
    }

    // Paused state visual configuration
    // Soft yellow bars at reduced opacity to clearly signal "paused" without extra icons
    readonly property color pausedBarColor: "#C9B458"
    readonly property real pausedDimOpacity: 0.55

    // Processing wave effect configuration (matches GTK implementation)
    // Creates flowing wave animation during transcription state
    readonly property QtObject processingConfig: QtObject {
        readonly property real waveSpeed: 0.12        // Faster than recording (0.08)
        readonly property real baseHeightBoost: 0.70  // 70% of height range used as base
        readonly property real harmonicStrength: 0.12 // Subtle 2x frequency harmonic
        readonly property real opacityMin: 0.75       // Opacity oscillates 0.75 - 1.0
        readonly property real opacityRange: 0.25
    }

    // Format elapsed seconds as MM:SS (matches GTK implementation)
    function formatElapsedTime(seconds: real): string {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
    }

    // Audio level from service (exposed for Repeater delegates under ComponentBehavior: Bound)
    readonly property real audioLevel: root.serviceAudioLevel

    // Animation time for audio bar noise (avoids Date.now() per-frame overhead)
    // Increments ~60 units per second for smooth sine wave oscillation
    property real animationTime: 0

    NumberAnimation on animationTime {
        running: (root.serviceState === "recording" || root.serviceState === "processing") && root.visibilities.stt
        from: 0
        to: 6000
        duration: 100000  // 100 seconds before loop (60 units/sec)
        loops: Animation.Infinite
    }

    // Cached bar gradient colors - invalidated only on theme change
    // Using explicit Connections instead of bindings prevents unnecessary recalculation
    property var barColors: []

    function updateBarColors() {
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

    // Pre-calculated wave offsets - computed once per frame instead of per-bar
    // Reduces Math.sin() calls from 1200/sec (20 bars × 60fps) to 60/sec
    readonly property var waveOffsets: {
        if (root.serviceState !== "recording") return [];
        const cfg = audioConfig;
        const offsets = [];
        for (let i = 0; i < barCount; i++) {
            // Sine wave oscillates around a baseline (e.g., waveVariation=0.30 → baseline=0.70)
            // This creates ±30% height variation while keeping bars visible
            const baseline = 1 - cfg.waveVariation;
            offsets.push(Math.sin(i * cfg.waveFrequency + animationTime * cfg.waveSpeed) * cfg.waveVariation + baseline);
        }
        return offsets;
    }

    // Processing wave data - computes both offsets and opacities in single pass
    // Fixes: negative values, duplicated wavePos calculation, inconsistent patterns
    readonly property var processingWaveData: {
        if (root.serviceState !== "processing") return { offsets: [], opacities: [] };
        const cfg = processingConfig;
        const offsets = [];
        const opacities = [];
        for (let i = 0; i < barCount; i++) {
            // Spatial phase: one full 2π wave cycle across all bars
            const spatialPhase = (i / (barCount - 1)) * 2 * Math.PI;
            // Temporal offset: scrolls the wave over time
            const wavePos = spatialPhase + animationTime * cfg.waveSpeed;

            // Primary wave: transforms sin [-1,1] to [0,1] - always positive
            const primaryWave = 0.5 + 0.5 * Math.sin(wavePos);
            // Harmonic adds texture at 2x frequency
            const harmonic = cfg.harmonicStrength * Math.sin(wavePos * 2);
            // Clamp to ensure non-negative (harmonic might push below 0)
            offsets.push(Math.max(0, primaryWave + harmonic));

            // Opacity follows same wave pattern
            opacities.push(cfg.opacityMin + cfg.opacityRange * primaryWave);
        }
        return { offsets, opacities };
    }

    // Expose arrays for bar access
    readonly property var processingWaveOffsets: processingWaveData.offsets
    readonly property var processingWaveOpacities: processingWaveData.opacities

    // State configuration map - defines visual properties for each state.
    // icon/iconColor are used by the state indicator Loader below.
    readonly property var stateMap: ({
        "recording": {
            icon: "mic",
            iconColor: Colours.palette.m3primary,
            statusText: qsTr("Recording..."),
            textColor: Colours.palette.m3onSurface
        },
        "paused": {
            icon: "pause",
            iconColor: Colours.palette.m3tertiary,
            statusText: qsTr("Paused"),
            textColor: Colours.palette.m3onSurface
        },
        "processing": {
            icon: "hourglass_top",
            iconColor: Colours.palette.m3secondary,
            statusText: qsTr("Transcribing..."),
            textColor: Colours.palette.m3onSurface
        },
        "error": {
            icon: "error",
            iconColor: Colours.palette.m3error,
            statusText: qsTr("Failed"),
            textColor: Colours.palette.m3error
        },
        "success": {
            icon: "check_circle",
            iconColor: Colours.palette.m3primary,
            statusText: qsTr("Done!"),
            textColor: Colours.palette.m3onSurface
        },
        "idle": {
            icon: "mic",
            iconColor: Colours.palette.m3onSurface,
            statusText: "",
            textColor: Colours.palette.m3onSurface
        }
    })

    // Current state config - falls back to idle for unknown states
    readonly property var stateConfig: stateMap[root.serviceState] ?? stateMap["idle"]

    // Language badge: maps ISO 639-1 codes to uppercase display labels
    readonly property var languageDisplayNames: ({
        "en": "EN", "es": "ES", "fr": "FR", "de": "DE",
        "pt": "PT", "it": "IT", "ja": "JA", "zh": "ZH"
    })
    readonly property string languageLabel: {
        if (root.serviceLanguage === "") return "";
        return languageDisplayNames[root.serviceLanguage] ?? root.serviceLanguage.toUpperCase();
    }

    // State indicator components - dispatched by the Loader in the content layout.
    // Shared icon component for paused and success (same structure, different icon/color).
    // When transitioning between these two states, Loader reuses the instance and
    // bindings update reactively — no destruction/recreation flicker.
    Component {
        id: stateIconComponent

        MaterialIcon {
            text: root.stateConfig.icon
            color: root.stateConfig.iconColor
            font.pointSize: Appearance.font.size.extraLarge
        }
    }

    // Success state: checkmark icon + delivery method subtitle
    Component {
        id: successComponent

        ColumnLayout {
            spacing: Appearance.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: root.stateConfig.icon
                color: root.stateConfig.iconColor
                font.pointSize: Appearance.font.size.extraLarge
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: text !== ""
                text: {
                    if (root.serviceInjectionDowngraded)
                        return qsTr("Pasted (submit skipped)");
                    switch (root.serviceInjectionPath) {
                        case "rpc":
                            return root.serviceInjectionSubmitted
                                ? qsTr("Submitted")
                                : qsTr("Injected");
                        case "paste": return qsTr("Pasted");
                        default: return qsTr("Copied");
                    }
                }
                color: root.serviceInjectionDowngraded
                    ? Colours.palette.m3error
                    : Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }
        }
    }

    Component {
        id: errorComponent

        ColumnLayout {
            spacing: Appearance.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: root.stateConfig.icon
                color: root.stateConfig.iconColor
                font.pointSize: Appearance.font.size.extraLarge
            }

            // Error summary (e.g., "Connection timed out", "Authentication failed")
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.serviceErrorDetail || qsTr("Transcription failed")
                font.pointSize: Appearance.font.size.normal
                color: Colours.palette.m3error
            }

            // Actionable hint (e.g., "Check your network connection")
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.serviceErrorHint || qsTr("Check STT configuration")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline
            }

            // Action buttons for error state
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Appearance.spacing.normal

                // Retry: re-submit audio (available for API errors where audio file exists)
                ControlButton {
                    id: retryBtn
                    visible: root.serviceErrorSource === "api" || root.serviceErrorSource === "timeout"
                    icon: "refresh"
                    iconColor: Colours.palette.m3primary
                    onClicked: root.job.retry()
                }

                // Cancel: discard audio, remove job card
                ControlButton {
                    id: errorCancelBtn
                    icon: "close"
                    iconColor: Colours.palette.m3error
                    onClicked: root.job.cancel()
                }

                // Copy raw error to clipboard
                ControlButton {
                    visible: root.serviceErrorRaw !== ""
                    icon: "content_copy"
                    onClicked: Quickshell.execDetached(["wl-copy", root.serviceErrorRaw])
                }
            }

            // Signal handler for error-state buttons (retryBtn, errorCancelBtn).
            // These IDs only exist inside errorComponent's scope, so this
            // Connections block must live here — the outer block below
            // handles recording/paused-state buttons instead.
            Connections {
                target: SttService
                function onActionTriggered(sessionId: string, action: string): void {
                    if (sessionId !== "" && sessionId !== root.job.sessionId) return;
                    if (root.serviceState !== "error") return;
                    if (action === "retry") retryBtn.triggerPress();
                    else if (action === "cancel") errorCancelBtn.triggerPress();
                }
            }
        }
    }

    /// Control button with press feedback animation.
    /// Call triggerPress() to programmatically trigger the scale squeeze
    /// (used by Connections block for keybind-triggered feedback).
    component ControlButton: Item {
        id: controlBtn

        required property string icon
        property color iconColor: Colours.palette.m3onSurfaceVariant

        signal clicked()

        function triggerPress(): void {
            pressAnim.restart();
        }

        SequentialAnimation {
            id: pressAnim

            NumberAnimation {
                target: controlBtn
                property: "scale"
                to: 0.85
                duration: 80
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: controlBtn
                property: "scale"
                to: 1.0
                duration: 150
                easing.type: Easing.OutBack
            }
        }

        implicitWidth: controlIcon.implicitWidth + Appearance.padding.normal * 2
        implicitHeight: controlIcon.implicitHeight + Appearance.padding.smaller * 2

        StyledRect {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Colours.palette.m3surfaceContainerHigh
        }

        StateLayer {
            radius: Appearance.rounding.full
            color: controlBtn.iconColor
            function onClicked(): void { controlBtn.clicked(); }
        }

        MaterialIcon {
            id: controlIcon
            anchors.centerIn: parent
            text: controlBtn.icon
            color: controlBtn.iconColor
            font.pointSize: Appearance.font.size.normal
        }
    }

    /// Radio-style delivery option chip for "ask" mode.
    /// Displays a selectable pill with icon + label. Visual feedback via triggerPress().
    component DeliveryOption: Item {
        id: optionBtn

        required property string mode
        required property string icon
        required property string label
        required property bool selected

        signal clicked()

        function triggerPress(): void {
            optionPressAnim.restart();
        }

        SequentialAnimation {
            id: optionPressAnim

            NumberAnimation {
                target: optionBtn
                property: "scale"
                to: 0.90
                duration: 80
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: optionBtn
                property: "scale"
                to: 1.0
                duration: 150
                easing.type: Easing.OutBack
            }
        }

        implicitWidth: optionRow.implicitWidth + Appearance.padding.normal * 2
        implicitHeight: optionRow.implicitHeight + Appearance.padding.smaller * 2

        StyledRect {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: optionBtn.selected
                ? Colours.palette.m3primaryContainer
                : Colours.palette.m3surfaceContainerHigh
        }

        StateLayer {
            radius: Appearance.rounding.full
            color: optionBtn.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            function onClicked(): void {
                root.job.setDeliveryChoice(optionBtn.mode);
                optionBtn.clicked();
            }
        }

        Row {
            id: optionRow
            anchors.centerIn: parent
            spacing: Appearance.spacing.smaller

            MaterialIcon {
                text: optionBtn.icon
                color: optionBtn.selected
                    ? Colours.palette.m3onPrimaryContainer
                    : Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: optionBtn.label
                color: optionBtn.selected
                    ? Colours.palette.m3onPrimaryContainer
                    : Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight + padding

    // Main container
    StyledRect {
        id: container

        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: Math.max(root.minDrawerWidth, content.implicitWidth + Appearance.padding.large * 2)
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        // Smooth height transitions when child elements appear/disappear
        // (e.g., timer hiding when transitioning from processing → success)
        Behavior on implicitHeight {
            Anim {}
        }

        radius: Appearance.rounding.normal
        color: "transparent"

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Appearance.spacing.normal

            // Language badge + elapsed timer on a single line above audio bars
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.serviceState === "recording" || root.serviceState === "paused" || root.serviceState === "processing"

                Row {
                    spacing: Appearance.spacing.smaller
                    opacity: root.serviceState === "paused" ? root.pausedDimOpacity : 1.0

                    StyledText {
                        visible: root.languageLabel !== ""
                        width: visible ? implicitWidth : 0
                        text: root.languageLabel
                        font.pointSize: Appearance.font.size.small
                        font.family: Appearance.font.family.mono
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        visible: root.languageLabel !== ""
                        width: visible ? implicitWidth : 0
                        text: "·"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        text: root.formatElapsedTime(root.serviceElapsedSeconds)
                        font.pointSize: Appearance.font.size.small
                        font.family: Appearance.font.family.mono
                        color: Colours.palette.m3outline
                    }
                }
            }

            // Audio level bars (visible during recording, paused, and processing)
            // Recording: audio-reactive with gentle wave
            // Paused: bars settle to minimum height (audioLevel reset to 0 on pause)
            // Processing: flowing wave animation (no audio input)
            FadeTransition {
                id: audioLevelContainer

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: audioLevelRow.implicitWidth
                Layout.preferredHeight: root.audioBarContainerHeight

                show: root.serviceState === "recording" || root.serviceState === "paused" || root.serviceState === "processing"

                Row {
                    id: audioLevelRow

                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.barCount

                        Rectangle {
                            id: bar

                            required property int index

                            // Bar height based on audio level and position
                            // Center bars are taller, edges shorter (bell curve effect)
                            readonly property real positionFactor: {
                                const center = root.barCount / 2;
                                const distance = Math.abs(index - center) / center;
                                return 1 - distance * 0.5;  // 0.5 to 1.0
                            }

                            // The "truth" - raw target from audio level (updates at 60fps)
                            readonly property real targetHeight: {
                                const cfg = root.audioConfig;

                                // Processing state: use processing wave with boosted base height
                                if (root.serviceState === "processing") {
                                    const procCfg = root.processingConfig;
                                    const waveMultiplier = root.processingWaveOffsets[index] ?? 1.0;
                                    // Base height at 70% of range, modulated by wave pattern
                                    const boostedHeight = procCfg.baseHeightBoost * (cfg.maxBarHeight - cfg.minBarHeight);
                                    const rawHeight = cfg.minBarHeight + boostedHeight * waveMultiplier * positionFactor;
                                    // Clamp to valid range (defensive, offsets should already be positive)
                                    return Math.max(cfg.minBarHeight, Math.min(cfg.maxBarHeight, rawHeight));
                                }

                                // Recording/paused: audio-reactive with gentle wave
                                const rawLevel = root.audioLevel;

                                // Noise gate: subtract ambient baseline, amplify, compress
                                let effectiveLevel = 0;
                                if (rawLevel > cfg.noiseFloor) {
                                    // Rescale: map [noiseFloor, 1.0] → [0, 1.0]
                                    effectiveLevel = (rawLevel - cfg.noiseFloor) / (1.0 - cfg.noiseFloor);
                                    // Gain: stretch narrow speech range to fill [0, 1.0]
                                    effectiveLevel = Math.min(1.0, effectiveLevel * cfg.gain);
                                    // Power curve compresses dynamic range (sqrt boosts mids)
                                    effectiveLevel = Math.pow(effectiveLevel, cfg.powerCurve);
                                }

                                // Use pre-calculated wave offset (computed once per frame at root level)
                                const waveOffset = root.waveOffsets[index] ?? 1.0;
                                return cfg.minBarHeight + effectiveLevel * (cfg.maxBarHeight - cfg.minBarHeight) * positionFactor * waveOffset;
                            }

                            // Opacity modulation for processing and paused states
                            readonly property real waveOpacity: {
                                if (root.serviceState === "processing") {
                                    const opacity = root.processingWaveOpacities[index];
                                    if (opacity !== undefined && opacity >= 0 && opacity <= 1) {
                                        return opacity;
                                    }
                                }
                                if (root.serviceState === "paused") {
                                    return root.pausedDimOpacity;
                                }
                                return 1.0;
                            }

                            // The "display" - smoothed version for rendering
                            property real smoothedHeight: root.audioConfig.minBarHeight

                            // Manual exponential smoothing - runs every time target changes
                            onTargetHeightChanged: {
                                smoothedHeight = smoothedHeight + (targetHeight - smoothedHeight) * root.audioConfig.smoothing;
                            }

                            // Direct sizing required because:
                            // 1. Row children can't use Layout.* properties (Row isn't a Layout)
                            // 2. anchors.verticalCenter conflicts with Row's child positioning
                            // 3. Therefore we calculate y manually for vertical centering
                            width: 5
                            height: smoothedHeight
                            y: (parent.height - height) / 2

                            radius: 2.5
                            color: root.serviceState === "paused" ? root.pausedBarColor : (root.barColors[index] ?? Colours.palette.m3primary)
                            opacity: waveOpacity
                        }
                    }
                }
            }

            // Control buttons: pause/resume, submit, restart, cancel (visible during recording/paused)
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter

                show: root.serviceState === "recording" || root.serviceState === "paused"

                RowLayout {
                    spacing: Appearance.spacing.normal

                    ControlButton {
                        id: pauseBtn
                        icon: root.serviceState === "paused" ? "play_arrow" : "pause"
                        iconColor: root.serviceState === "paused" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        onClicked: root.job.recording ? root.job.pause() : root.job.resume()
                    }

                    // Restart is service-level (cancel current + start new job),
                    // not per-job, so it calls the orchestrator directly.
                    ControlButton {
                        id: restartBtn
                        icon: "restart_alt"
                        onClicked: SttService.restart()
                    }

                    ControlButton {
                        id: cancelBtn
                        icon: "close"
                        iconColor: Colours.palette.m3error
                        onClicked: root.job.cancel()
                    }

                    ControlButton {
                        id: submitBtn
                        icon: "check"
                        iconColor: Colours.palette.m3confirm
                        onClicked: root.job.stop()
                    }
                }
            }

            // Delivery mode radio toggle (visible only in "ask" mode during recording/paused).
            // Hidden during processing to match convention that processing is non-interactive.
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.serviceIsAskMode && (root.serviceState === "recording"
                    || root.serviceState === "paused")

                RowLayout {
                    spacing: Appearance.spacing.small

                    DeliveryOption {
                        id: saveOption
                        mode: "clipboard"
                        icon: "content_copy"
                        label: qsTr("Save")
                        selected: root.serviceDeliveryChoice === "clipboard"
                    }

                    DeliveryOption {
                        id: injectOption
                        mode: "inject"
                        icon: "input"
                        label: qsTr("Inject")
                        selected: root.serviceDeliveryChoice === "inject"
                    }

                    DeliveryOption {
                        id: submitOption
                        mode: "submit"
                        icon: "send"
                        label: qsTr("Submit")
                        selected: root.serviceDeliveryChoice === "submit"
                    }
                }
            }

            // Signal handler for recording/paused-state buttons (pauseBtn, restartBtn,
            // cancelBtn, submitBtn) and delivery mode radio options.
            // These IDs exist in the main content scope.
            // The error-state buttons have a separate Connections block inside
            // errorComponent above.
            Connections {
                target: SttService
                function onActionTriggered(sessionId: string, action: string): void {
                    if (sessionId !== "" && sessionId !== root.job.sessionId) return;
                    switch (action) {
                        case "pause":
                        case "resume":
                            pauseBtn.triggerPress();
                            break;
                        case "restart":
                            restartBtn.triggerPress();
                            break;
                        case "cancel":
                            if (root.serviceState !== "error")
                                cancelBtn.triggerPress();
                            break;
                        case "retry":
                            break;
                        case "stop":
                            submitBtn.triggerPress();
                            break;
                        case "mode-clipboard":
                            saveOption.triggerPress();
                            break;
                        case "mode-inject":
                            injectOption.triggerPress();
                            break;
                        case "mode-submit":
                            submitOption.triggerPress();
                            break;
                    }
                }
            }

            // State indicator - dispatches to the appropriate component per state.
            // recording/processing/idle/paused → null (audio bars + control buttons handle these)
            // success → stateIconComponent (checkmark icon driven by stateMap)
            // error → errorComponent (icon + hint text)
            Loader {
                Layout.alignment: Qt.AlignHCenter

                sourceComponent: {
                    switch (root.serviceState) {
                        case "success":
                            return successComponent;
                        case "error":
                            return errorComponent;
                        default:
                            return null;
                    }
                }
            }
        }
    }
}
