pragma ComponentBehavior: Bound

import qs.components
import QtQuick
import QtQuick.Shapes

/// The brightness dial: a camera iris whose blades open and let light through.
///
/// Visuals only — value handling, drag and wheel live in RotaryControl.
///
/// The recess ring and the rim reuse RotaryKnob's values, so brightness and
/// volume read as two controls milled from one panel even though their
/// mechanisms differ. Geometry lives in RotaryControl's 176-unit design space
/// and was tuned against real-size renders (84 px canvas inside the OSD card).
///
/// Three things here are deliberate and were each the fix for a specific defect
/// found by reviewing a screen recording. Do not undo them without re-reviewing:
///
///  - Every blade is its OWN Shape with its OWN gradient. An earlier version
///    drew one annulus with one gradient across it and painted seam lines on
///    top; on video that read as a flat hubcap, because a single gradient
///    crossing all six wedges uninterrupted is exactly what a one-piece disc
///    looks like. Six lit facets is the whole illusion.
///  - The aperture follows sqrt(value), not value. A diaphragm passes light in
///    proportion to its AREA, so a radius linear in value puts nearly all the
///    visible change above 50% and makes 6% and 40% indistinguishable.
///  - The bloom sits ABOVE the blades. Light bleeding over the blade edges is
///    what sells "coming through the opening"; a halo around the outer rim only
///    ever reads as a glow effect applied to the whole object.
RotaryControl {
    id: root

    /// Drives the shutter gesture: the iris sweeps open as the OSD arrives and
    /// snaps shut as it leaves, instead of sliding away frozen at its last value.
    required property bool revealed

    readonly property int bladeCount: 6
    readonly property real bladeStep: 360 / bladeCount
    // These three radii must stay separated. When the blade edge and the rim
    // stroke landed on the same radius, their antialiased edges interfered and
    // the rim rendered as a dashed arc at real size — a moiré, not a stroke bug.
    // Keep at least ~2 design units between each pair.
    readonly property real bladeOuterRadiusUnits: 70
    readonly property real rimRadiusUnits: 72.5
    readonly property real recessRadiusUnits: 79
    readonly property real apertureMaxUnits: 66

    /// The whole disc is the control — there is no surrounding scale to miss.
    hitSize: 2 * bladeOuterRadiusUnits

    // ── Blade geometry, measured off a real diaphragm ─────────────────────────
    //
    // A blade is a TRIANGLE anchored to the housing, not a wedge of the disc.
    // Two of its corners sit on the rim, `rimSpan` apart; the third is a tip
    // that plunges toward the centre. Because the tip leads the arc by
    // `tipLeadDegrees`, each blade spans about 96° while the blades are only 60°
    // apart — so every blade lies across its neighbour, and what you see is a
    // stack of leaves rather than a tiled pie. The opening is whatever polygon
    // their straight leading edges leave in the middle.
    //
    // The numbers come from measuring a reference diaphragm animation and
    // rescaling from its 288-unit rim to this 70-unit one: rim footprint 58°,
    // tip 38° ahead of the arc, tip radius sweeping 31→275 of 288 (here 6→66 of
    // 70) and the whole rim footprint turning ~52° over the travel.

    /// The blade's footprint on the housing. Constant — a real blade is rigid.
    /// Deliberately WIDER than the 60° between blades: at the reference's 58° the
    /// footprints leave a 2° gap that fans out into a visible hairline of
    /// background between every pair of leaves. Overlapping on the rim as well as
    /// at the tip means no gap can open at any aperture.
    readonly property real rimSpanDegrees: 64
    /// How far the tip leads its own rim arc. This is what makes blades overlap:
    /// at 38° each blade covers 96°, well past the 60° between them.
    readonly property real tipLeadDegrees: 38
    /// How far the rim footprint turns over the full travel.
    readonly property real spinDegrees: 52
    /// Where the key light hangs, in the same degree convention as the blades
    /// (0 = right, -90 = up). Upper left, matching RotaryKnob's baked highlight.
    readonly property real lightAngle: -125

    readonly property int openDuration: 360
    readonly property int shutDuration: 150

    // Animated imperatively rather than through `Behavior on reveal`. A Behavior
    // would need its duration to depend on `revealed` — the very property whose
    // change starts the animation — and both bindings hang off the same change
    // signal, so the animation can start while `duration` still holds the value
    // computed for the PREVIOUS direction, silently swapping the sweep and the
    // snap. Driving it from the handler makes the direction unambiguous.
    property real reveal: 0

    Anim {
        id: revealAnim

        target: root
        property: "reveal"
    }

    function playReveal(): void {
        revealAnim.stop();
        revealAnim.from = root.reveal;
        revealAnim.to = root.revealed ? 1 : 0;
        revealAnim.duration = root.revealed ? root.openDuration : root.shutDuration;
        revealAnim.start();
    }

    onRevealedChanged: playReveal()

    // A dial built while the OSD is ALREADY showing — the Loader swaps dials on
    // a metric change, so this is the normal case for volume → brightness — must
    // still sweep. An initial binding of `reveal` would have started it wide open,
    // because animations never run on a property's first evaluation.
    Component.onCompleted: {
        if (revealed)
            playReveal();
    }

    /// 0 = fully shut, 1 = wide open. Everything mechanical derives from this
    /// single number, so the blades, the spin and the light can never disagree.
    readonly property real openness: reveal * Math.sqrt(Math.max(0, animatedValue))

    readonly property real centreX: width / 2
    readonly property real centreY: height / 2
    readonly property real bladeRadius: u(bladeOuterRadiusUnits)
    /// Distance from the centre to a blade tip — and therefore the circumradius
    /// of the opening the blades leave, since the tips ARE its corners. Scales
    /// straight off `openness` with no floor, so `reveal` reaching 0 drives the
    /// tips onto the centre and the shutter genuinely shuts. The sqrt inside
    /// `openness` already keeps low brightness values apart.
    readonly property real apertureRadius: u(apertureMaxUnits) * openness
    readonly property real spin: openness * spinDegrees

    /// Light is a physical thing, not a theme role, so this is NOT taken from
    /// Colours: the palette is monochrome (warm-neutral), and routing the glow
    /// through a surface role would either tint it grey or drag in a hue that
    /// appears nowhere else in the shell. Near-white with a faint warm bias
    /// reads as a lit panel without inventing an accent. The metal is pushed
    /// slightly cool below to widen that contrast.
    readonly property color lightColour: Qt.rgba(1, 0.965, 0.91, 1)

    /// Machined steel from shadow (0) to specular (1), biased blue-grey.
    function metal(level: real): color {
        const t = Math.max(0, Math.min(1, level));
        return Qt.rgba(0.20 + 0.58 * t, 0.22 + 0.585 * t, 0.25 + 0.585 * t, 1);
    }

    // ── Spill: the faint wash the assembly throws on the card around it ──
    // Deliberately weak. It is ambience, not the story — the story is the bloom
    // over the blades further down.
    //
    // Reaches exactly u(88) — half of RotaryControl's 176-unit design box, so the
    // glow stops at the dial's own bounds. It used to overdraw to u(94), which
    // left under a pixel of clearance to the PillCard edge once the dial and the
    // card were sized to match: the readout, the spacing and the dial fill the
    // card's interior to within 3.5 px, and the glow was eating 2.65 of them.
    // Do not push this past 88 without redoing that budget.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.04 + root.openness * 0.34

        ShapePath {
            strokeWidth: -1

            fillGradient: RadialGradient {
                centerX: root.centreX
                centerY: root.centreY
                centerRadius: root.u(88)
                focalX: centerX
                focalY: centerY

                // Starts at zero alpha: a radial gradient fills everything inside
                // its FIRST stop with that stop's colour, so a first stop partway
                // out paints a flat opaque core instead of fading in.
                GradientStop { position: 0.00; color: Qt.alpha(root.lightColour, 0) }
                GradientStop { position: 0.76; color: Qt.alpha(root.lightColour, 0) }
                GradientStop { position: 0.85; color: Qt.alpha(root.lightColour, 0.18) }
                GradientStop { position: 1.00; color: Qt.alpha(root.lightColour, 0) }
            }

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.u(94)
                radiusY: root.u(94)
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // ── Recess the assembly sits in (same values as RotaryKnob's) ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.round(root.u(2 * root.recessRadiusUnits))
        height: width
        radius: width / 2
        color: Qt.rgba(0.015, 0.018, 0.022, 0.94)
        border.width: Math.max(1, root.u(2))
        border.color: Qt.rgba(0.42, 0.45, 0.48, 0.32)
    }

    // ── The opening, drawn as a disc and then covered by the blades, so the
    //    visible silhouette is exactly the rounded polygon they leave. ──
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.apertureRadius > 0.5
        // Scaled by `reveal` as well as by value, so the light dims in step with
        // the closing blades instead of blazing behind a shut diaphragm.
        opacity: root.reveal * (0.4 + root.animatedValue * 0.6)

        ShapePath {
            strokeWidth: -1

            fillGradient: RadialGradient {
                centerX: root.centreX
                centerY: root.centreY
                centerRadius: Math.max(0.01, root.apertureRadius)
                focalX: centerX
                focalY: centerY

                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 1) }
                GradientStop { position: 0.62; color: Qt.alpha(root.lightColour, 0.94) }
                GradientStop { position: 1.00; color: Qt.alpha(root.lightColour, 0.62) }
            }

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: Math.max(0.01, root.apertureRadius)
                radiusY: Math.max(0.01, root.apertureRadius)
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // ── The blades: six independent surfaces, each lit on its own ──
    Item {
        id: bladeRing

        anchors.fill: parent

        Repeater {
            model: root.bladeCount

            // Anchored to `bladeRing` by id rather than to `parent`, because a
            // Repeater delegate has no parent during its first binding pass.
            delegate: Shape {
                id: blade

                required property int index

                anchors.fill: bladeRing
                preferredRendererType: Shape.CurveRenderer

                /// Leading end of this blade's footprint on the rim. The arc runs
                /// BACKWARD from here by rimSpanDegrees; the tip leads it.
                readonly property real rimLead: root.spin + index * root.bladeStep - 90
                readonly property real tipAngle: rimLead + root.tipLeadDegrees
                /// Points into the blade's own body, roughly where its mass sits —
                /// used only for lighting.
                readonly property real bisector: rimLead - root.rimSpanDegrees / 2

                /// How squarely this blade faces the key light. Because it is
                /// computed from an angle that carries `spin`, every blade
                /// brightens and dims as the iris turns — the highlight travels
                /// around the ring instead of being painted on.
                readonly property real facing: 0.5 + 0.5 * Math.cos((bisector - root.lightAngle) * Math.PI / 180)

                readonly property real tipX: root.centreX + root.apertureRadius * Math.cos(tipAngle * Math.PI / 180)
                readonly property real tipY: root.centreY + root.apertureRadius * Math.sin(tipAngle * Math.PI / 180)
                readonly property real rimLeadX: root.centreX + root.bladeRadius * Math.cos(rimLead * Math.PI / 180)
                readonly property real rimLeadY: root.centreY + root.bladeRadius * Math.sin(rimLead * Math.PI / 180)

                ShapePath {
                    // A hairline of its own darkness along every edge. With
                    // overlapping blades this is what separates one leaf from the
                    // one beneath it — the old design needed a separate ring of
                    // seam rectangles because its blades merely abutted.
                    strokeColor: Qt.rgba(0.03, 0.035, 0.045, 0.85)
                    strokeWidth: Math.max(1, root.u(1.6))
                    joinStyle: ShapePath.MiterJoin

                    // Runs from the rim toward the tip, so each face is brightest
                    // at the edge nearest the opening — the aperture lighting the
                    // metal it passes.
                    fillGradient: LinearGradient {
                        x1: root.centreX + root.bladeRadius * Math.cos(blade.bisector * Math.PI / 180)
                        y1: root.centreY + root.bladeRadius * Math.sin(blade.bisector * Math.PI / 180)
                        x2: blade.tipX
                        y2: blade.tipY

                        GradientStop { position: 0.00; color: root.metal(blade.facing * 0.62) }
                        GradientStop { position: 0.55; color: root.metal(blade.facing * 0.86) }
                        GradientStop { position: 1.00; color: root.metal(blade.facing * 1.05 + 0.06) }
                    }

                    // Rim footprint, swept backward from the leading end.
                    PathAngleArc {
                        centerX: root.centreX
                        centerY: root.centreY
                        radiusX: root.bladeRadius
                        radiusY: root.bladeRadius
                        startAngle: blade.rimLead
                        sweepAngle: -root.rimSpanDegrees
                        moveToStart: true
                    }

                    // Trailing rim corner -> tip. This straight edge is the one
                    // that cuts the opening.
                    PathLine {
                        x: blade.tipX
                        y: blade.tipY
                    }

                    // Tip -> back to the leading rim corner, closing the triangle.
                    PathLine {
                        x: blade.rimLeadX
                        y: blade.rimLeadY
                    }
                }
            }
        }
    }

    // NOTE: there is deliberately no ring of seam rectangles here any more. The
    // old blades merely abutted, so the joins had to be drawn on top as separate
    // radial bars. These blades genuinely lie across one another, so each one's
    // own dark stroke IS the join, and the leaf beneath shows through under it.

    // ── Bloom: light bleeding over the blade edges. Sits ABOVE the metal on
    //    purpose — this is the layer that makes the light look like it is
    //    escaping through the opening rather than pasted onto it. ──
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.apertureRadius > 0.5
        opacity: root.reveal * (0.22 + root.animatedValue * 0.58)

        ShapePath {
            strokeWidth: -1

            fillGradient: RadialGradient {
                centerX: root.centreX
                centerY: root.centreY
                centerRadius: Math.max(0.01, root.apertureRadius * 2.3)
                focalX: centerX
                focalY: centerY

                GradientStop { position: 0.00; color: Qt.alpha(root.lightColour, 0.55) }
                GradientStop { position: 0.36; color: Qt.alpha(root.lightColour, 0.34) }
                GradientStop { position: 0.62; color: Qt.alpha(root.lightColour, 0.13) }
                GradientStop { position: 1.00; color: Qt.alpha(root.lightColour, 0) }
            }

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: Math.max(0.01, root.apertureRadius * 2.3)
                radiusY: Math.max(0.01, root.apertureRadius * 2.3)
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // ── Rim (same colour as RotaryKnob's knob border), sitting just clear of the
    //    blade edge so the two antialiased contours do not fight.
    //
    //    Stroked as a Shape, NOT as a Rectangle with `color: "transparent"` and a
    //    border: Qt draws that case with the rounded-rect shader, and a fully
    //    transparent fill meeting a thin border produces a stippled, dashed-
    //    looking arc. RotaryKnob gets away with a Rectangle because its rings are
    //    filled. Do not "simplify" this back to a Rectangle.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(0.82, 0.84, 0.85, 0.9)
            strokeWidth: Math.max(1, root.u(2))
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.u(root.rimRadiusUnits)
                radiusY: root.u(root.rimRadiusUnits)
                startAngle: 0
                sweepAngle: 360
            }
        }
    }
}
