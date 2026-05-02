import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

// CLAYMORPHISM display-pill primitive — for STATIC display elements only.
//
// Used by the top bar's clock, date, weather, workspaces, sys tray, system
// indicators — anything that DISPLAYS information without state changes.
// Also used as static icon containers inside cards (e.g. the Coffee /
// screen_record icon circles in the utilities popup).
//
// Aesthetic: claymorphism (warm, decorative, ambient depth)
//   - Two opposing outer shadows (light NW + dark SE) → convex extrusion
//   - Hairline border → crisp edge definition that survives on busy
//     backgrounds (top bar pills sit over the wallpaper directly)
//   - Visible top rim highlight → "polished, lit-from-above" warmth
//
// Sister primitives — different roles, different aesthetics:
//   - PillToggleSurface — INTERACTIVE controls (toggles, action buttons).
//     Pure dark-monochrome NEUMORPHISM with raised↔inset state signaling.
//     Standalone (doesn't extend PillSurface), so PillSurface tuning here
//     does NOT affect interactive controls.
//   - PillCard — CONTENT-FRAMING containers. Claymorphism with softer
//     wider shadows and a faint bottom inner-shadow (more "embedded
//     panel" than "raised chip").
//
// The boundary is STATIC vs INTERACTIVE, not visual-vs-functional. Static
// elements have no state to signal, so neumorphism's depth-direction
// vocabulary is wasted on them — claymorphism's decorative warmth is more
// appropriate. Interactive elements EARN the strict neumorphic recipe
// because they actually have state to communicate.
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
    // Hairline 1px from the shared pill palette — defining feature of the
    // claymorphism look here, and survives on busy backgrounds (top bar
    // pills sit directly over the wallpaper). Without it, shadows alone
    // wash out on bright wallpaper regions and the pill silhouette
    // disappears.
    property color borderColor: _defaultStyle.border
    property real borderWidth: 1

    // --- Two-shadow convex depth (claymorphic) ---------------------------
    // Slightly asymmetric offsets (y > x on the dark shadow) mimic an
    // overhead light source — feels more organic than a perfect diagonal.
    // Wider blur than PillToggleSurface's interactive controls to lean
    // claymorphic (warm ambient depth) rather than neumorphic (austere
    // contained depth).
    property real darkShadowOffsetX: 2
    property real darkShadowOffsetY: 3
    property real darkShadowBlur: 12
    property real darkShadowAlpha: 0.40

    property real lightShadowOffsetX: -2
    property real lightShadowOffsetY: -2
    property real lightShadowBlur: 8
    property real lightShadowAlpha: 0.10

    // --- Inner rim highlight (clay-derived) ------------------------------
    // Visible top rim — defining claymorphism cue. The bottom inner shadow
    // stays at 0 by default (heavy bottom-inner shadow makes pure
    // claymorphism feel dated); consumers that want the full "embedded"
    // feel can opt in by setting `innerShadowAlpha`.
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
