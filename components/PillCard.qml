import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

// Section-card container — CLAYMORPHISM half of the shell's two-tier
// design hierarchy. Where PillSurface / PillToggleSurface use strict
// dark-monochrome NEUMORPHISM (austere, depth-only state signaling),
// PillCard leans warmly claymorphic: softer wider shadows, a top rim
// highlight, and a faint bottom inner-shadow that gives the surface an
// "embedded warm panel" feel.
//
// Why two aesthetics, not one:
//
//   The two styles complement each other along the visual hierarchy.
//   The card draws the eye first (warm, glowing, rounded) and frames a
//   content region. The pills inside are cooler and more austere, which
//   makes them read clearly as INTERACTIVE elements against the card's
//   ambient warmth. Active toggles' inset depressions only sell the
//   "pressed" feel against a uniform same-color surface — that surface
//   IS the claymorphism card. The two styles aren't competing; the card
//   provides the stage, the pills perform the state.
//
// Three deliberate differences from PillSurface:
//
//   1. NO CLIPPING by default. Cards frequently host popovers (dropdown
//      menus, animated overflow chips) that must render past the card
//      bounds. Use `clipContent: true` to opt back in for cases like
//      IdleInhibit's slide-out activity chip.
//
//   2. Dimmer default fill (m3surfaceContainerLow vs ContainerHigh on
//      pills). This preserves the visual hierarchy when pills are nested
//      inside cards — the card recedes, the pills protrude. Without this
//      differentiation, same-tier nested pills would visually disappear
//      into the card.
//
//   3. CLAYMORPHIC depth recipe (vs PillSurface's neumorphic recipe):
//      larger softer shadows, visible top rim highlight, faint bottom
//      inner-shadow. Cards are bigger surfaces and benefit from a warmer
//      embedded feel; reducing the recipe to pure neumorphism would
//      collapse them into "just another flat surface."
//
// Default radius is `rounding.normal` (not `.full`) — cards are not capsules.

Item {
    id: root

    // --- Fill ------------------------------------------------------------
    // Cached default so color + borderColor share a single pillStyle() call.
    readonly property var _defaultStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerLow, Colours.glass.subtle)

    property color color: _defaultStyle.background
    property real radius: Appearance.rounding.normal

    // --- Border ----------------------------------------------------------
    property color borderColor: _defaultStyle.border
    property real borderWidth: 1

    // --- Two-shadow convex depth (claymorphic) ---------------------------
    // Wider blur and slightly larger offsets than the neumorphic pill
    // primitives — claymorphism wants softer, more diffuse shadows that
    // wrap the element in ambient depth rather than the contained, sharp-
    // edged depth of neumorphism. Tuned to land between "too glowy"
    // (original 18 blur was a halo against busy wallpaper) and "too austere"
    // (the previous 10 blur stripped away the warmth we want for cards).
    property real darkShadowOffsetX: 3
    property real darkShadowOffsetY: 4
    property real darkShadowBlur: 14
    property real darkShadowAlpha: 0.28

    property real lightShadowOffsetX: -3
    property real lightShadowOffsetY: -3
    property real lightShadowBlur: 11
    property real lightShadowAlpha: 0.07

    // --- Inner rim highlight (clay-derived) ------------------------------
    // The defining claymorphism cues — a visible top rim that catches
    // overhead light + a faint bottom inner-shadow that grounds the card
    // as "embedded into the panel." These overlays are what differentiate
    // the warm claymorphic card from the cool neumorphic pills inside it.
    // Without them, the card would collapse into another neumorphic surface
    // and lose its role as the visual frame.
    property real highlightAlpha: 0.08
    property real innerShadowAlpha: 0.03

    // --- Clipping --------------------------------------------------------
    // Default false: cards may host popovers that overflow card bounds
    // (e.g. SplitButton dropdowns). Opt-in for cases with intentional
    // overflow that should be hidden (e.g. IdleInhibit's slide-out chip).
    property alias clipContent: cardBody.clip

    // Default slot — children are reparented into contentHolder, which fills
    // the card body. Layouts using `anchors.fill: parent` resolve against
    // contentHolder, which itself fills cardBody, so consumer geometry is
    // identical to the prior StyledRect-based layout.
    default property alias content: contentHolder.data

    // Dark shadow (bottom-right) — declared first so it paints furthest back.
    RectangularShadow {
        anchors.fill: cardBody
        radius: cardBody.radius
        blur: root.darkShadowBlur
        spread: 0
        offset.x: root.darkShadowOffsetX
        offset.y: root.darkShadowOffsetY
        color: Qt.rgba(0, 0, 0, root.darkShadowAlpha)
    }

    // Light shadow (top-left).
    RectangularShadow {
        anchors.fill: cardBody
        radius: cardBody.radius
        blur: root.lightShadowBlur
        spread: 0
        offset.x: root.lightShadowOffsetX
        offset.y: root.lightShadowOffsetY
        color: Qt.rgba(1, 1, 1, root.lightShadowAlpha)
    }

    StyledRect {
        id: cardBody

        anchors.fill: parent
        color: root.color
        radius: root.radius
        border.width: root.borderWidth
        border.color: root.borderColor
        // clip: see root.clipContent alias (default false)

        // Inner rim/contact gradient — top rim highlight + faint bottom
        // inner shadow. Always instantiated so per-instance overrides take
        // effect without a Loader. visible flag short-circuits the paint
        // when both alphas are zero.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            visible: root.highlightAlpha > 0 || root.innerShadowAlpha > 0

            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, root.highlightAlpha) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.00) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, root.innerShadowAlpha) }
            }
        }

        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }
}
