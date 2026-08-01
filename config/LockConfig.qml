import Quickshell.Io

JsonObject {
    property bool recolourLogo: false
    property bool enableFprint: true
    property int maxFprintTries: 3
    property Sizes sizes: Sizes {}
    property Beams beams: Beams {}

    component Sizes: JsonObject {
        property real heightMult: 0.7
        property real ratio: 16 / 9
        property int centerWidth: 600
    }

    // Tuning for the metallic beams background (components/effects/BeamsBackground.qml
    // → assets/shaders/beams.frag). Exposed as config rather than hardcoded
    // because these are LOOK values that want iterating, and shell.json reloads
    // live — so a lock/unlock cycle is enough to see a change, with no shell
    // restart and no shader recompile.
    component Beams: JsonObject {
        // --- material -----------------------------------------------------
        // These reproduce the React Bits reference; calibrated by headless render
        // sweeps. See docs/beams-background.md before changing them.
        // Rate of the travelling wave in the height field. This is the ONLY
        // continuous motion in the effect; `revealDuration` below governs the
        // one-shot wipe and is independent of it.
        property real speed: 1.0
        property real noiseScale: 0.1
        property real grain: 1.75
        property real beamWidth: 2.6
        property real rotation: 30 // degrees
        property real roughness: 0.3
        property real lightIntensity: 0.028
        property real ambient: 0.007
        property real edgeDarken: 0.18

        // Second, much broader specular lobe sitting under the tight one. A
        // single lobe reads as plastic; the pair is what gives the bands breadth.
        property real sheenRoughness: 0.75
        property real sheenStrength: 0.12
        // Schlick term. On this surface it only fires on the steep flanks of the
        // height field, i.e. the beam edges, so it sharpens edges without
        // washing out the flats.
        property real fresnel: 0.8

        // --- reveal animation ---------------------------------------------
        // stagger = beam-to-beam offset, growSpan = how far along a beam the
        // front travels. Only their RATIO matters: it sets the DIRECTION of the
        // wipe. The shader renormalises the total, so the duration is always
        // exactly one sweep regardless of these values.
        property real stagger: 0.55
        property real growSpan: 0.45

        // THE knob for the two staged looks:
        //   0 = one straight diagonal front sweeping the screen (beams have no
        //       individual identity)
        //   1 = beams arrive one after another as discrete objects, each still
        //       filling along its own length
        // Intermediate values blend the two.
        property real beamQuantise: 1.0

        // Softness of the front, as a fraction of the sweep.
        property real feather: 0.14
        // Brightness added right at the moving front, so it reads as the beams
        // being drawn rather than as a rectangle of opacity sliding across.
        property real frontGlow: 0.5
        // false: each beam fills from its bottom-left end toward its top-right
        // end. true: the other way.
        property bool growFlip: false

        // How long the wipe takes. Longer than any Appearance.anim token on
        // purpose — this is a deliberate dramatic beat, not a UI micro-interaction.
        property int revealDuration: 1400
    }
}
