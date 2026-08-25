pragma ComponentBehavior: Bound

import ".."
import Quickshell
import QtQuick

// Material finish overlay for the surface primitives.
//
// Everything here is driven by a Theme recipe block, and every layer is guarded
// on its own alpha being > 0. Under the clay theme all alphas are zero, so
// nothing paints and clay renders exactly as it did before the theme system
// existed. Under metal these five layers are what separate "dark rounded
// rectangle" from "machined surface".
//
// The layers, in paint order — this order is load-bearing:
//
//   1. sheen   vertical, lightens the top half        (broad form)
//   2. sweep   horizontal, one soft bright band       (broad form)
//   3. grain   static anisotropic micro-texture       (material)
//   4. rimTop  hard bright line on the top edge       (crisp detail)
//   5. rimBot  dim line on the bottom edge            (crisp detail)
//
// Broad form first, then the material that textures it, then the crisp edge
// details on top so the grain does not eat them.
//
// Why the SWEEP matters most: uniform lighting is what makes a dark rounded
// rectangle read as plastic. Real metal is a near-mirror, so the light source
// lands in ONE place and falls off — brightness varies ALONG the piece. A
// single soft horizontal band buys most of that read for one gradient.
//
// Deliberately NOT animated. Real metal microstructure is static — only
// reflections move. A time-scrolled texture makes the surface appear to crawl
// independently of the UI and reads as fake; this was established empirically
// before the port. If motion is wanted later it belongs on the SWEEP (a
// highlight that responds to hover/focus), never on the grain.
Item {
    id: root

    // intentional var: heterogeneous JS recipe block from Theme (Theme.pill etc.)
    required property var recipe

    property real radius: 0

    // Scales the LIT layers (sheen, sweep, both rims) without touching the grain.
    //
    // The grain is the material itself and should persist through every state;
    // the rest is lighting, and lighting is what a state change modulates.
    // PillToggleSurface drives this from `raisedFactor` so a pressed toggle
    // loses its highlights — a surface depressed into its housing is in shadow —
    // while still reading as the same machined material.
    property real specularFactor: 1.0

    // --- Sweep geometry, clamped so the gradient stops stay ordered ----------
    // A GradientStop list must be strictly increasing; letting the recipe push
    // the centre to 0 or 1 would collapse two stops onto each other. Clamping
    // the centre away from the edges keeps `left < centre < right` by
    // construction, so no recipe value can produce an invalid gradient.
    readonly property real _sweepCentre: Math.max(0.08, Math.min(0.92, recipe?.sweepCentre ?? 0.5))
    readonly property real _sweepHalf: Math.max(0.02, (recipe?.sweepWidth ?? 0.3) / 2)
    readonly property real _sweepLeft: Math.max(0.0, _sweepCentre - _sweepHalf)
    readonly property real _sweepRight: Math.min(1.0, _sweepCentre + _sweepHalf)

    // Same guarantee for the rim stops: a recipe value of 0 would land a stop
    // exactly on 0.0 (top rim) or 1.0 (bottom rim), colliding with the fixed
    // stop already there and producing a duplicate-position gradient.
    readonly property real _rimStop: Math.max(0.002, Math.min(0.98, recipe?.rimStop ?? 0.05))
    readonly property real _rimBottomStop: Math.max(0.002, Math.min(0.98, recipe?.rimBottomStop ?? 0.05))

    // NOTE on the `recipe?.x ?? <literal>` reads throughout this file: the
    // literals are belt-and-braces against a malformed recipe, NOT the
    // authoritative defaults. Every real default lives in services/Theme.qml,
    // whose contract is that each recipe block is written out in full. Do not
    // tune the look by editing the fallbacks here — they should never be the
    // value in play.

    // 1. Vertical sheen — lightens the top of the body and falls off by
    // mid-height. Makes the surface read as a curved extrusion catching
    // overhead light rather than a flat swatch.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: (root.recipe?.sheenTop ?? 0) * root.specularFactor > 0

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(1, 1, 1, (root.recipe?.sheenTop ?? 0) * root.specularFactor)
            }
            GradientStop {
                position: 0.55
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(1, 1, 1, 0)
            }
        }
    }

    // 2. Horizontal specular sweep — the reflection of the light source.
    // Deliberately off-centre: a band centred at 0.5 reads as a symmetric
    // gloss stamp (every pill identically lit), which looks mechanical. Placing
    // it off-centre makes the lighting read as directional.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: (root.recipe?.sweepAlpha ?? 0) * root.specularFactor > 0

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0.0
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: root._sweepLeft
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: root._sweepCentre
                color: Qt.rgba(1, 1, 1, (root.recipe?.sweepAlpha ?? 0) * root.specularFactor)
            }
            GradientStop {
                position: root._sweepRight
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(1, 1, 1, 0)
            }
        }
    }

    // 3. Brushed micro-texture. The tile is 96x96 noise smeared horizontally with
    // wraparound, so it is seamless and anisotropic — vertical detail stays
    // sharp, horizontal detail smears, which reads as "machined". The smear is
    // deliberately SHORT (~2px correlation): an earlier 9px smear produced
    // streaks long enough to read as wood grain instead of metal. Tiled (not
    // stretched) so grain size stays constant regardless of surface width.
    //
    // StyledClippingRect, because the gradient layers self-clip via their own
    // `radius` but a tiled Image cannot — and QML's `clip: true` clips only to
    // the bounding RECTANGLE, so square grain corners would poke out past the
    // rounded silhouette on any primitive whose body isn't already a clipping
    // rect (PillCard's body is a plain StyledRect).
    //
    // Loader rather than `visible: false`, because unlike the gradient layers
    // (plain Rectangles, near-free when hidden) this one costs a real clip node
    // plus a tiled texture on EVERY surface in the shell. Under clay
    // brushedAlpha is 0, so without the Loader every pill, toggle and card would
    // carry a clip node it never draws through.
    Loader {
        anchors.fill: parent
        active: (root.recipe?.brushedAlpha ?? 0) > 0

        sourceComponent: StyledClippingRect {
            radius: root.radius
            color: "transparent"

            Image {
                anchors.fill: parent
                source: `${Quickshell.shellDir}/assets/textures/brushed-noise.png`
                fillMode: Image.Tile
                opacity: root.recipe?.brushedAlpha ?? 0
                smooth: false
                cache: true
            }
        }
    }

    // 4. Top rim — a hard bright line along the very top edge. Under metal this
    // replaces clay's broad `highlightAlpha` wash: clay spreads soft light
    // everywhere, metal concentrates it into one edge. `rimStop` is a fraction
    // of the surface height, so the line stays visually thin on a 30px pill and
    // on a 200px card alike.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: (root.recipe?.rimAlpha ?? 0) * root.specularFactor > 0

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(1, 1, 1, (root.recipe?.rimAlpha ?? 0) * root.specularFactor)
            }
            GradientStop {
                position: root._rimStop
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(1, 1, 1, 0)
            }
        }
    }

    // 5. Bottom rim — the bevel catching reflected fill light from below. Much
    // dimmer than the top. This is the cue that reads as a machined EDGE with
    // thickness: with only a top rim the surface looks like a lit sheet, with
    // both it looks like a solid piece you could pick up.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: (root.recipe?.rimBottomAlpha ?? 0) * root.specularFactor > 0

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: 1.0 - root._rimBottomStop
                color: Qt.rgba(1, 1, 1, 0)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(1, 1, 1, (root.recipe?.rimBottomAlpha ?? 0) * root.specularFactor)
            }
        }
    }
}
