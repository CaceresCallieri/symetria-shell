import QtQuick

// The two-axis "pressed into the panel" gradient — the shell's depth cue for an
// ACTIVE surface.
//
// WHY THIS EXISTS AS A COMPONENT: this pair of gradients was open-coded in three
// places (PillToggleSurface, ActiveIndicator, the calendar's today cell) and two
// of the copies had frozen with clay's numbers written as literals
// (`Qt.rgba(0, 0, 0, 0.55)`, `× 0.5`). Those copies therefore kept drawing
// CLAY's depression after the shell's default material became metal, which is
// visible as the bar's active workspace and today's date still looking like the
// old design language while the quick toggles moved on. Each copy even carried a
// comment claiming it matched the others — the comments stayed true and the code
// did not.
//
// Alphas are passed in rather than read from Theme here on purpose:
// PillToggleSurface exposes them as per-instance overridable properties, and
// reading the recipe internally would silently drop those overrides.
//
// The geometry, which is the part worth not re-deriving:
//
//   Vertical axis, full strength
//     top    → darkAlpha   (shadow falling into the well from overhead)
//     bottom → lightAlpha  (reflected fill light from below)
//
//   Horizontal axis, scaled by horizontalWeight
//     left   → darkAlpha  × weight
//     right  → lightAlpha × weight
//
// The two composite: the top-left corner takes shadow from BOTH passes and is
// the darkest point, bottom-right takes light from both and is the brightest,
// and the off-diagonals partially cancel. That yields the diagonal well without
// a true 2D radial gradient, which QML's Gradient API cannot express. The
// vertical bias is what keeps the lighting direction agreeing with the raised
// pills' overhead-light shadows, so the whole shell reads as lit from one place.
Item {
    id: root

    property real darkAlpha: 0
    property real lightAlpha: 0
    property real horizontalWeight: 0.5

    // Animated strength. PillToggleSurface drives this from its inset factor so
    // the cue fades in as the raised cues fade out; static consumers leave it 1.
    property real factor: 1.0

    property real radius: 0

    visible: factor > 0.01 && (darkAlpha > 0 || lightAlpha > 0)

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.00
                color: Qt.rgba(0, 0, 0, root.darkAlpha * root.factor)
            }
            GradientStop {
                position: 0.45
                color: Qt.rgba(0, 0, 0, 0.00)
            }
            GradientStop {
                position: 0.55
                color: Qt.rgba(1, 1, 1, 0.00)
            }
            GradientStop {
                position: 1.00
                color: Qt.rgba(1, 1, 1, root.lightAlpha * root.factor)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0.00
                color: Qt.rgba(0, 0, 0, root.darkAlpha * root.horizontalWeight * root.factor)
            }
            GradientStop {
                position: 0.45
                color: Qt.rgba(0, 0, 0, 0.00)
            }
            GradientStop {
                position: 0.55
                color: Qt.rgba(1, 1, 1, 0.00)
            }
            GradientStop {
                position: 1.00
                color: Qt.rgba(1, 1, 1, root.lightAlpha * root.horizontalWeight * root.factor)
            }
        }
    }
}
