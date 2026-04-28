import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

// Shared visual primitive for every "pill" in the shell.
//
// Current aesthetic: HYBRID (neumorphism depth + modern hairline polish)
//   - Two opposing outer shadows (light NW + dark SE) → convex extrusion
//     read that neumorphism contributes
//   - Hairline border → crisp edge definition even on transparent/wallpaper
//     backgrounds where neumorphism alone would wash out
//   - Subtle top rim highlight (inner gradient top half only) → "polished"
//     feel without the heavy inner-bottom-shadow that made claymorphism
//     read as dated
//
// This occupies the stylistic space of macOS Sonoma/Sequoia pill buttons,
// Arc browser chrome, current Fluent UI: directional shadow + fine border
// + light top rim.
//
// To switch aesthetic later, edit this file; all pill consumers stay
// untouched. Public property API is preserved across aesthetics so
// consumer overrides (e.g. ProjectGroup's borderWidth/borderColor
// animation) continue to work.
//
// Two usage patterns:
//
//   1. Content-outside (pill is a *background* behind centered content):
//        Item {
//            PillSurface { anchors.fill: parent; color: ... }
//            SomeCenteredContent { anchors.centerIn: parent }
//        }
//
//   2. Content-inside (children need rounded-corner clipping):
//        PillSurface {
//            color: ...
//            SomeFullBleedOverlay { anchors.fill: parent }
//            RowLayout { anchors.centerIn: parent; ... }
//        }

Item {
    id: root

    // --- Fill ------------------------------------------------------------
    // Default style cached once — both color and borderColor share the same
    // Colours.pillStyle() result so we avoid calling it twice per instance/change.
    readonly property var _defaultStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    property color color: _defaultStyle.background
    property real radius: Appearance.rounding.full

    // --- Border ----------------------------------------------------------
    // Flat props (not a `border` group) so Item-based consumers can bind
    // and animate them directly: `Behavior on borderWidth { Anim {} }`.
    //
    // Hairline border from the shared pill palette — gives the pill a
    // crisp silhouette on transparent/wallpaper-backed bars where the
    // shadows alone would leave the edge vague.
    property color borderColor: _defaultStyle.border
    property real borderWidth: 1

    // --- Two-shadow convex depth (neumorphism-derived) -------------------
    // Slightly asymmetric offsets (y > x on the dark shadow) mimic a
    // natural overhead light source rather than a perfect 45° diagonal,
    // which feels more organic than pure neumorphism.
    property real darkShadowOffsetX: 2
    property real darkShadowOffsetY: 3
    property real darkShadowBlur: 12
    property real darkShadowAlpha: 0.40

    property real lightShadowOffsetX: -2
    property real lightShadowOffsetY: -2
    property real lightShadowBlur: 8
    property real lightShadowAlpha: 0.10

    // --- Inner rim highlight (clay-derived, dialed back) -----------------
    // Subtle top rim light only; the heavy bottom inner shadow that
    // made pure claymorphism feel dated is kept at 0 by default.
    property real highlightAlpha: 0.08
    property real innerShadowAlpha: 0.0

    // Default slot: children declared inside PillSurface { ... } get reparented
    // into contentHolder, which fills the pill body and is clipped to the
    // rounded shape.
    default property alias content: contentHolder.data

    // Dark shadow (bottom-right) — declared FIRST so it renders furthest
    // back. Paint order in an Item without explicit z is declaration order.
    RectangularShadow {
        anchors.fill: pillBody
        radius: pillBody.radius
        blur: root.darkShadowBlur
        spread: 0
        offset.x: root.darkShadowOffsetX
        offset.y: root.darkShadowOffsetY
        color: Qt.rgba(0, 0, 0, root.darkShadowAlpha)
    }

    // Light shadow (top-left).
    RectangularShadow {
        anchors.fill: pillBody
        radius: pillBody.radius
        blur: root.lightShadowBlur
        spread: 0
        offset.x: root.lightShadowOffsetX
        offset.y: root.lightShadowOffsetY
        color: Qt.rgba(1, 1, 1, root.lightShadowAlpha)
    }

    StyledClippingRect {
        id: pillBody

        anchors.fill: parent
        color: root.color
        radius: root.radius
        border.width: root.borderWidth
        border.color: root.borderColor

        // Inner rim/contact gradient — top rim highlight renders by default
        // (highlightAlpha: 0.08); innerShadowAlpha defaults to 0 so the bottom
        // band is off. Rectangle is always instantiated so consumers that change
        // the alphas per-instance see immediate effect without a Loader.
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

        // Holder for consumer content (default slot). anchors.fill so children
        // naturally use `anchors.fill: parent` / `anchors.centerIn: parent`
        // against pill bounds.
        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }
}
