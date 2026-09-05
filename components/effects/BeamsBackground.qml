pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Animated metallic beams — a 2D port of the React Bits <Beams /> background.
//
// The shader (assets/shaders/beams.frag) does all the work; this wrapper exists
// to give it a readable API and own the time animation.
//
// Tuning values arrive via `cfg` rather than being read from Config here: this
// lives in components/effects/ and must not know that a lock screen exists, or
// a second consumer would silently inherit lock-screen tuning it cannot
// override. The shape of `cfg` is the schema in config/LockConfig.qml
// (component Beams).
//
// The item paints with PREMULTIPLIED alpha: revealed area is opaque, unrevealed
// area is fully transparent. That is what lets it wipe in over whatever sits
// behind it — on the lock screen, the desktop screencopy.
Item {
    id: root

    // 0 = nothing covered, 1 = fully covered. Animate this to play the wipe.
    property real reveal: 1

    // Drives the travelling wave in the height field. Left running so the
    // surface keeps breathing after the wipe finishes — a frozen frame reads as
    // wallpaper, not as a lit scene.
    //
    // Deliberately NOT throttled by us: when the compositor blanks the output
    // (DPMS) it stops sending frame callbacks, so Qt's render loop idles on its
    // own. Adding a manual timer here would only make the motion stutter while
    // the screen IS on, for no saving while it is off.
    property bool animating: true

    // Phase of the travelling wave, in seconds. Driven by the animation below;
    // settable directly only to reproduce a deterministic frame.
    property real time: 0

    // intentional var: heterogeneous tuning block, see config/LockConfig.qml
    required property var cfg

    NumberAnimation on time {
        running: root.animating && root.visible
        loops: Animation.Infinite
        from: 0
        // Long ramp rather than a short loop, for two reasons: the noise is
        // sampled at time * uSpeed * 3, so a short period would make the wave
        // visibly repeat — and every wrap back to 0 is a DISCONTINUITY in the
        // height field, i.e. a one-frame jump. A day-long ramp puts that jump
        // beyond any plausible lock session instead of every ten minutes.
        to: 86400
        duration: 86400000
    }

    ShaderEffect {
        anchors.fill: parent

        // Uniform names must match the shader's `buf` block exactly — Qt maps
        // QML properties to uniforms BY NAME. Renaming one here silently drops
        // it (the uniform keeps its zero-initialised value) rather than erroring,
        // so treat these names as a contract with assets/shaders/beams.frag.
        //
        // time is clamped: it is reachable from shell.json (focusBackdrop.time)
        // and unbounded input loses float32 precision in the shader's noise
        // lookup, rendering garbage. 86400 matches the animation's own upper
        // ramp, so the lock screen never notices the clamp.
        property real time: Math.min(Math.max(root.time, 0), 86400)
        property real uSpeed: root.cfg.speed
        property real uScale: root.cfg.noiseScale
        property real uNoiseIntensity: root.cfg.grain
        property real uBeamWidth: root.cfg.beamWidth
        property real uRotation: root.cfg.rotation * Math.PI / 180
        property real uRoughness: root.cfg.roughness
        property real uLightIntensity: root.cfg.lightIntensity
        property real uAmbient: root.cfg.ambient
        property real uEdgeDarken: root.cfg.edgeDarken

        property real uReveal: root.reveal
        property real uStagger: root.cfg.stagger
        property real uGrowSpan: root.cfg.growSpan
        property real uBeamQuantise: root.cfg.beamQuantise
        property real uFeather: root.cfg.feather
        property real uFrontGlow: root.cfg.frontGlow
        property real uGrowFlip: root.cfg.growFlip ? 1 : 0

        property real uSheenRoughness: root.cfg.sheenRoughness
        property real uSheenStrength: root.cfg.sheenStrength
        property real uFresnel: root.cfg.fresnel

        property vector2d uResolution: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))

        // Deliberately NOT config-driven, unlike every other parameter above:
        // the calibrations in docs/beams-background.md — the gain on D, the
        // ambient level, the vignette falloff — were all solved against a white
        // light along this direction. Exposing these would let a tint or angle
        // change silently invalidate them.
        property vector4d uLightColour: Qt.vector4d(1, 1, 1, 1)
        property vector4d uLightDir: Qt.vector4d(0, 3, 10, 0)

        fragmentShader: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/shaders/beams.frag.qsb`)

        // Blending is on by default, but state it: the whole design depends on
        // the unrevealed region compositing away to show what is underneath.
        blending: true

        onStatusChanged: {
            if (status === ShaderEffect.Error)
                console.warn("[BeamsBackground] shader failed to compile:", log);
        }
    }
}
