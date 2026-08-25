import qs.components.effects
import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

// THEMED: structure lives here, material numbers come from `Theme.toggle`.
// The `*Max` suffix on the depth properties is local vocabulary — it means
// "value at full raised/inset strength", since each is multiplied by an
// animated factor. Theme recipes use the unsuffixed names.
// The prose below describes the CLAY recipe. The SHIPPED DEFAULT is now
// METAL — see `material` in services/Theme.qml. Clay is still first-class,
// reachable with `symmetria shell surface material clay`.
//
// Tier 2 toggle-button surface — pill primitive whose visual state encodes
// "is this on?" via two reinforcing cues: a brighter body color *and* an
// inverse-neumorphism (inset / debossed) shadow when active. The pill keeps
// the same outline shape across states; what changes is depth direction.
//
//   raised: true && active: false  → "raised" claymorphism:
//       two opposing OUTER drop shadows + 1px border + inner top rim light.
//       Reads as "you can press this."
//   raised: true && active: true   → "pressed in" inverse neumorphism:
//       OUTER shadows fade out (it's no longer floating above the surface),
//       border stays (crisp edge), and an INNER gradient overlay paints a
//       dark band along the top edge (shadow falling into the well) + a
//       subtle light band along the bottom edge (reflected fill light).
//       Body color is also brightened. Reads as "this is on / pressed."
//   raised: false                  → always flat (Tier 3 pure-action):
//       no depth, no inset. `active` still toggles color.
//
// Two animated factors drive every depth cue:
//   depthFactor  = raised ? 1 : 0          (any depth at all)
//   insetFactor  = raised && active ? 1 : 0 (depth direction reversed)
//   raisedFactor = depthFactor × (1 − insetFactor)
//                                           (raised cues only — outer
//                                            shadows + top rim light)
// Both animate via Behaviors so the toggle transition cross-fades the raised
// cues out and the inset cues in smoothly.
//
// Use PillSurface for static *display* pills (time, system, workspace).
// Use PillToggleSurface for *interactive* toggle buttons.

Item {
    id: root

    // --- State -----------------------------------------------------------
    property bool active: false
    property bool raised: true

    // --- Colors ----------------------------------------------------------
    // Default style cached once — inactiveColor and borderColor share the same
    // Colours.pillStyle() result so we avoid calling it twice per instance/change.
    readonly property var _defaultStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    // American spelling matches QML's Color type convention (not the project's Colour convention).
    property color inactiveColor: _defaultStyle.background
    property color activeColor: Colours.palette.m3primary
    property color borderColor: _defaultStyle.border

    // FORM axis multiplier — see PillSurface.qml.
    property real radius: Appearance.rounding.full * Theme.layout.surfaceRounding

    // --- Tunable depth params (apply when raised && !active) -------------
    // Values come from the active theme; the rationale below is CLAY's.
    //
    // Reference-aligned dark neumorphism: SHORT-RANGE blur (shadow stays
    // close to the pill edge — no outer-glow halo) but STRONG alpha (so the
    // depth cue actually reads against PillCard's solid backdrop). Reference
    // shadows are visibly punchy, just contained. Top rim highlight near
    // zero so dual shadows alone define the raised silhouette. Border width
    // dropped to zero — drawn outlines compete with shadow-defined edges.
    //
    // Metal inverts that last point: its silhouette is defined by a drawn
    // edge plus a hard specular rim rather than by shadow spread, so it sets
    // borderWidth to 1. Do not re-hardcode these — see services/Theme.qml.
    property real darkShadowOffsetX: Theme.toggle.darkShadowOffsetX
    property real darkShadowOffsetY: Theme.toggle.darkShadowOffsetY
    property real darkShadowBlur: Theme.toggle.darkShadowBlur
    property real darkShadowAlphaMax: Theme.toggle.darkShadowAlpha

    property real lightShadowOffsetX: Theme.toggle.lightShadowOffsetX
    property real lightShadowOffsetY: Theme.toggle.lightShadowOffsetY
    property real lightShadowBlur: Theme.toggle.lightShadowBlur
    property real lightShadowAlphaMax: Theme.toggle.lightShadowAlpha

    property real highlightAlphaMax: Theme.toggle.highlightAlpha
    property real borderWidthMax: Theme.toggle.borderWidth

    // --- Inverse-neumorphism (inset / pressed-in) depth params ----------
    // Applied when raised && active. The depression's depth is composed
    // along TWO axes for a true diagonal "well" effect (matching the
    // reference where dark concentrates at top-LEFT and light at bottom-
    // RIGHT, not just top↔bottom):
    //
    //   Vertical axis (full strength):
    //     top  → darkInsetAlpha (shadow falling into the well from overhead)
    //     bottom → lightInsetAlpha (reflected fill light from below)
    //
    //   Horizontal axis (weighted by horizontalInsetWeight, default 50%):
    //     left  → darkInsetAlpha × weight  (rim shadow continuing down-side)
    //     right → lightInsetAlpha × weight (fill-light wrapping up-side)
    //
    // The two gradients composite: top-left corner gets shadow from BOTH
    // axes (deepest dark), bottom-right corner gets light from both
    // (brightest highlight), off-diagonals partially cancel. This produces
    // the classical neumorphic diagonal-inset look without needing a true
    // 2D radial gradient (which QML's Gradient API doesn't support).
    //
    // Vertical bias keeps the lighting direction consistent with the
    // raised pills' overhead-light dual shadows — the whole shell feels
    // lit from the same direction.
    property real darkInsetAlpha: Theme.toggle.darkInsetAlpha
    property real lightInsetAlpha: Theme.toggle.lightInsetAlpha
    property real horizontalInsetWeight: Theme.toggle.horizontalInsetWeight

    // --- Finish override --------------------------------------------------
    // See the matching properties on PillSurface. `specularFactor` defaults to
    // raisedFactor, which zeroes the lit layers when the pill presses in — a
    // surface depressed into its housing is in shadow.
    //
    // A consumer overrides that ONLY for a part that is both inset AND
    // polished, which is a real thing rather than a contradiction: the lip of a
    // worn socket catches light precisely because it is a recess something has
    // been seated into repeatedly. Without the override such a part renders
    // with no highlights at all and reads as a flat coloured swatch — which is
    // the failure this override was added to fix.
    // intentional var: heterogeneous JS recipe block from Theme
    property var finishRecipe: Theme.toggle
    property real specularFactor: raisedFactor

    // --- Animation duration for the active↔inactive transition ----------
    property int transitionDuration: Appearance.anim.durations.normal

    // Default content slot — children are reparented into the clipped pill body.
    default property alias content: contentHolder.data

    // Animated depth factors. depthFactor = "any depth at all";
    // insetFactor = "depth is inverted (pressed in)". raisedFactor is a derived
    // "raised cues only" multiplier so outer shadows + top rim light fade out
    // exactly when the inset cues fade in.
    //
    // INTERNAL — do NOT set these from outside. Drive the depth state via `raised`
    // and `active`. Writing these directly would desync the state machine (the
    // Behavior would animate from the external value, not from raised/active).
    property real depthFactor: raised ? 1.0 : 0.0
    property real insetFactor: raised && active ? 1.0 : 0.0
    readonly property real raisedFactor: depthFactor * (1.0 - insetFactor)

    Behavior on depthFactor {
        NumberAnimation {
            duration: root.transitionDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on insetFactor {
        NumberAnimation {
            duration: root.transitionDuration
            easing.type: Easing.OutCubic
        }
    }

    // Outer shadows — only render in the raised state. Multiplying by
    // raisedFactor (not depthFactor) so they fade out smoothly when the pill
    // transitions to inset / pressed-in.
    RectangularShadow {
        anchors.fill: pillBody
        radius: pillBody.radius
        blur: root.darkShadowBlur
        spread: 0
        offset.x: root.darkShadowOffsetX
        offset.y: root.darkShadowOffsetY
        color: Qt.rgba(0, 0, 0, root.darkShadowAlphaMax * root.raisedFactor)
        visible: root.raisedFactor > 0.01
    }

    RectangularShadow {
        anchors.fill: pillBody
        radius: pillBody.radius
        blur: root.lightShadowBlur
        spread: 0
        offset.x: root.lightShadowOffsetX
        offset.y: root.lightShadowOffsetY
        color: Qt.rgba(1, 1, 1, root.lightShadowAlphaMax * root.raisedFactor)
        visible: root.raisedFactor > 0.01
    }

    StyledClippingRect {
        id: pillBody

        anchors.fill: parent
        // Body color animates via StyledClippingRect's built-in CAnim Behavior.
        color: root.active ? root.activeColor : root.inactiveColor
        radius: root.radius
        border.width: root.borderWidthMax * root.depthFactor
        border.color: root.borderColor

        // Raised-cue overlay: top-only rim highlight. Visible only when the
        // pill is in the raised state (raisedFactor) — fades out as the pill
        // transitions to inset.
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            visible: root.raisedFactor > 0.01

            gradient: Gradient {
                GradientStop {
                    position: 0.00
                    color: Qt.rgba(1, 1, 1, root.highlightAlphaMax * root.raisedFactor)
                }
                GradientStop {
                    position: 0.55
                    color: Qt.rgba(1, 1, 1, 0.00)
                }
                GradientStop {
                    position: 1.00
                    color: Qt.rgba(0, 0, 0, 0.00)
                }
            }
        }

        // Inset cue — see components/effects/InsetDepression.qml for the
        // geometry. The alphas stay declared on this primitive rather than
        // being read from Theme inside the effect, because consumers override
        // them per instance.
        InsetDepression {
            anchors.fill: parent
            radius: root.radius
            darkAlpha: root.darkInsetAlpha
            lightAlpha: root.lightInsetAlpha
            horizontalWeight: root.horizontalInsetWeight
            factor: root.insetFactor
        }

        // Material finish (sheen + brushed grain + specular rim). Renders
        // nothing under clay. `specularFactor: raisedFactor` fades the LIT
        // layers out as the toggle presses in — the grain stays, because the
        // material doesn't change, only the lighting does. Declared before
        // contentHolder so it paints UNDER the toggle's content.
        SurfaceFinish {
            anchors.fill: parent
            radius: root.radius
            recipe: root.finishRecipe
            specularFactor: root.specularFactor
        }

        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }
}
