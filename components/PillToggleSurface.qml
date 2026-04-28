import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

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

    property real radius: Appearance.rounding.full

    // --- Tunable depth params (apply when raised && !active) -------------
    // Slightly stronger than PillSurface defaults — toggles want to feel more
    // tactile so users get a clear "press me" cue.
    property real darkShadowOffsetX: 2
    property real darkShadowOffsetY: 4
    property real darkShadowBlur: 14
    property real darkShadowAlphaMax: 0.45

    property real lightShadowOffsetX: -2
    property real lightShadowOffsetY: -2
    property real lightShadowBlur: 10
    property real lightShadowAlphaMax: 0.12

    property real highlightAlphaMax: 0.16
    property real borderWidthMax: 1

    // --- Inverse-neumorphism (inset / pressed-in) depth params ----------
    // Applied when raised && active. The dark inset band along the top sells
    // the "well" effect; the light band at the bottom is a subtle fill-light
    // reflection that grounds the pill so it doesn't read as just a dark
    // smudge.
    property real darkInsetAlpha: 0.35
    property real lightInsetAlpha: 0.10

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
            radius: parent.radius
            color: "transparent"
            visible: root.raisedFactor > 0.01

            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, root.highlightAlphaMax * root.raisedFactor) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, 0.00) }
            }
        }

        // Inset-cue overlay: dark band along the top edge (shadow falling
        // into the well) + subtle light band at the bottom (reflected fill).
        // Visible only when raised && active. This is the inverse neumorphism
        // pressed-in effect — the dominant cue that the toggle is "on."
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            visible: root.insetFactor > 0.01

            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, root.darkInsetAlpha * root.insetFactor) }
                GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.00) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, root.lightInsetAlpha * root.insetFactor) }
            }
        }

        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }
}
