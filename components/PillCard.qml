import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

// Section-card sibling to PillSurface — same visual family, different role.
//
// Where PillSurface frames a single interactive pill (button / toggle / badge),
// PillCard frames a *group* of content (a panel section, a row of toggles,
// a labeled card). Three deliberate differences from PillSurface:
//
//   1. NO CLIPPING by default. Cards frequently host popovers (dropdown menus,
//      animated overflow chips) that must render past the card bounds. Use
//      `clipContent: true` to opt back in for cases like IdleInhibit's slide-
//      out activity chip.
//
//   2. Dimmer default fill (m3surfaceContainerLow vs ContainerHigh on pills).
//      This preserves the visual hierarchy when pills are nested inside cards
//      — the card recedes, the pills protrude. Without this differentiation,
//      same-tier nested pills would visually disappear into the card.
//
//   3. Slightly more neumorphic dial: larger blur radii (cards are bigger
//      surfaces, need softer shadows to read as one cohesive panel rather
//      than a sharp button), modestly stronger top rim, and a faint bottom
//      inner shadow that adds a subtle "embedded into the panel" feel.
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

    // --- Two-shadow convex depth (neumorphism-derived) -------------------
    // Tighter, shorter-range shadows — the previous wider blur read as an
    // outer glow halo against the wallpaper backdrop rather than as a panel
    // resting on the surface. Reference neumorphism keeps shadow extent
    // proportionally close to the element edge so the depth cue reads as
    // "embedded into a uniform surface," not "floating in glow."
    property real darkShadowOffsetX: 2
    property real darkShadowOffsetY: 3
    property real darkShadowBlur: 10
    property real darkShadowAlpha: 0.22

    property real lightShadowOffsetX: -2
    property real lightShadowOffsetY: -2
    property real lightShadowBlur: 8
    property real lightShadowAlpha: 0.05

    // --- Inner rim highlight (clay-derived) ------------------------------
    // Dialed down toward pure neumorphism: minimal top rim, no bottom inner
    // shadow. The reference aesthetic relies on dual outer shadows alone to
    // define depth; the rim highlight was a claymorphism polish that made
    // the surface look "wet/glossy" rather than the matte material we want.
    property real highlightAlpha: 0.04
    property real innerShadowAlpha: 0.0

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
