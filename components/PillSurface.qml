import qs.components.effects
import qs.config
import qs.services
import QtQuick
import QtQuick.Effects

// Display-pill primitive — for STATIC display elements only.
//
// THEMED: this file owns the STRUCTURE of a display pill; the numbers that give
// it a material character come from `Theme.pill`. Switching Theme.material
// restyles every pill live (QML re-evaluates these bindings automatically).
// The prose below describes the CLAY recipe. The SHIPPED DEFAULT is now
// METAL — see `material` in services/Theme.qml. Clay is still first-class,
// reachable with `symmetria shell surface material clay`.
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
    // FORM axis multiplier: 1 keeps the configured rounding, 0 squares the
    // plate. Paired with barTopBleed in the same recipe — see services/Theme.qml
    // for why a rounded plate must never bleed off-screen.
    property real radius: Appearance.rounding.full * Theme.layout.surfaceRounding

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
    property real borderWidth: Theme.pill.borderWidth

    // --- Two-shadow convex depth -----------------------------------------
    // Under clay: slightly asymmetric offsets (y > x on the dark shadow) mimic
    // an overhead light source, with a wider blur than PillToggleSurface's
    // interactive controls — warm ambient depth rather than austere contained
    // depth. Metal drops BOTH outer shadows to zero — a flat plate casts no
    // convex halo; its silhouette comes from the border plus SurfaceFinish's
    // sweep. See the recipe comments in services/Theme.qml.
    //
    // These stay plain writable properties so consumers can still override per
    // instance (several do); binding to Theme only changes the DEFAULT.
    property real darkShadowOffsetX: Theme.pill.darkShadowOffsetX
    property real darkShadowOffsetY: Theme.pill.darkShadowOffsetY
    property real darkShadowBlur: Theme.pill.darkShadowBlur
    property real darkShadowAlpha: Theme.pill.darkShadowAlpha

    property real lightShadowOffsetX: Theme.pill.lightShadowOffsetX
    property real lightShadowOffsetY: Theme.pill.lightShadowOffsetY
    property real lightShadowBlur: Theme.pill.lightShadowBlur
    property real lightShadowAlpha: Theme.pill.lightShadowAlpha

    // --- Inner rim highlight ---------------------------------------------
    // Clay: a visible broad top rim, no bottom inner shadow (a heavy one makes
    // claymorphism feel dated). Metal zeroes BOTH — the broad wash and the
    // inner shadow are convex/embedded cues that a flat plate does not have;
    // SurfaceFinish's sweep and rim carry the lighting instead.
    property real highlightAlpha: Theme.pill.highlightAlpha
    property real innerShadowAlpha: Theme.pill.innerShadowAlpha

    // --- Finish override --------------------------------------------------
    // Which SurfaceFinish recipe paints the sheen / sweep / grain / rims.
    // Defaults to this role's own block; a consumer swaps in `Theme.engaged`
    // for a part that is worn bright (see that block in services/Theme.qml).
    //
    // Kept SEPARATE from `color` on purpose: the body colour says what the part
    // is made of, this says how its surface has been finished. Bundling them
    // would mean a caller could not brighten one without the other, which is
    // precisely the mistake — a pale body with a matte finish is plastic.
    // intentional var: heterogeneous JS recipe block from Theme
    property var finishRecipe: Theme.pill

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
            radius: root.radius
            color: "transparent"
            visible: root.highlightAlpha > 0 || root.innerShadowAlpha > 0

            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, root.highlightAlpha) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.00) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, root.innerShadowAlpha) }
            }
        }

        // Material finish (sheen + brushed grain + specular rim). Renders
        // nothing under clay — all four of its alphas are zero there. Declared
        // before contentHolder so it paints UNDER the pill's content.
        SurfaceFinish {
            anchors.fill: parent
            radius: root.radius
            recipe: root.finishRecipe
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
