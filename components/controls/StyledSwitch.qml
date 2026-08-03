import ".."
import qs.services
import qs.config
import QtQuick
import QtQuick.Templates

// A SLOT with a KNOB sliding in it — not a track with a pill.
//
// The previous build filled the thumb with raw `m3onSurface` (#eee5da) and the
// track with a lightened accent. Neither went through Colours.pillStyle(), so
// the active material never touched them: under metal this was the only
// near-white filled shape anywhere in the shell, and it read as a Material
// Design control pasted onto a machined panel.
//
// The rebuild says what a machined switch actually is:
//
//   slot  a groove cut into the panel. PillToggleSurface with `active: true`
//         unconditionally — a groove is a groove in both states, so it always
//         takes the inset gradient and never the raised specular. Constant
//         colour; it is the housing, not the signal.
//   knob  a plate that slides in the groove. PillSurface, so it carries the
//         material's own edge, sweep and grain. It is the ONLY part that
//         changes state.
//
// NO GLYPH. There is no check/cross drawn on the knob: position plus colour
// carries the state, and a switch is the one control where position alone is
// already unambiguous. (The glyph the previous build drew was invisible
// whenever the switch was ON anyway — it stroked m3onSurface onto an
// m3onSurface thumb — so nothing that was ever legible has been lost.)
//
// ON is therefore: the knob has travelled, and it has gone from cold machined
// grey to warm POLISHED metal via Colours.engagedPillStyle(). That helper
// deliberately breaks the material's lightness ceiling; see its comment in
// services/Colours.qml for why an engaged part is allowed to and a container
// is not.
//
// The tonal budget is the constraint worth knowing. Metal's neutral surfaces
// span only lightness 0.042–0.097, so the OFF knob has very little room to
// separate from the slot by tone. It is deliberately given the very top of that
// span while the slot sits near the bottom, and most of the actual separation
// is carried by the knob's 1px lifted edge rather than by its face. (Deliberately
// stated as a relation and not as hex values: the palette is user-editable in
// ~/.config/symmetria/shell.json, so literals here would drift out of date
// silently.) ON is where the contrast budget was spent instead — the polished
// engaged body, plus the lit finish on top.
//
// That ON body is lifted MORE than the connected socket's, even though both are
// "engaged" — see Colours.polish for the measurement behind that. The short
// version: a small disc ringed by a shadowed groove reads dimmer than the same
// value sitting flat on a card, so matching the numbers would NOT match the
// look.
//
// The edge is doing that OFF-state work, NOT the specular rim. `rimStop` is
// 0.020 of the surface HEIGHT, and the knob is ~27px, so the rim band is about
// half a pixel and lands entirely inside the border it would otherwise sit
// above. It is still correct to let PillSurface draw it (the recipe should not
// special-case small surfaces), but do not reason about the OFF knob's
// legibility as though the rim contributes — it does not at this scale.
//
// UNVERIFIED under clay: the structure should degrade to a raised neumorphic
// knob in a well, but the knob is a PillSurface reparented into the slot's
// clipping body, so clay's outer drop shadows are rendered INSIDE the slot's
// clip region and are likely cut off at the slot edge and at the knob's travel
// extremes. Metal is unaffected (all its shadow alphas are zero) and is the
// shipped default, so this was not chased. If clay is ever made default again,
// check this first — the fix is to declare the knob as a sibling of the slot
// rather than a child, or to inset it far enough to clear darkShadowBlur.
Switch {
    id: root

    // The groove is constant — the housing carries no state. Cached once so
    // background and border come from the same call and the edge keeps
    // matching the face.
    readonly property var _slotStyle: Colours.pillStyle(Colours.palette.m3surfaceContainer, Colours.glass.subtle)

    // Full intensity in BOTH states: the knob wants the top of whatever range
    // is available to it. OFF takes the ordinary surface recipe and lands at
    // the material ceiling; ON takes the engaged recipe and goes past it.
    readonly property var _knobStyle: checked ? Colours.engagedPillStyle(Colours.palette.m3primary, 1.0, Colours.polish.inGroove) : Colours.pillStyle(Colours.palette.m3surfaceContainerHighest, 1.0)

    implicitWidth: implicitIndicatorWidth
    implicitHeight: implicitIndicatorHeight

    indicator: PillToggleSurface {
        id: slot

        active: true
        activeColor: root._slotStyle.background
        borderColor: root._slotStyle.border

        implicitWidth: implicitHeight * 1.7
        implicitHeight: Appearance.font.size.normal + Appearance.padding.smaller * 2

        // NOTE on sizing in this scope: read the SLOT by id, never `parent`.
        // PillToggleSurface reparents its default-slot children into an internal
        // content holder that is anchors.fill'd, so `parent` has a real
        // width/height but NO implicitWidth / implicitHeight and no radius.
        //
        // Reading `parent.width` instead is a trap of its own and was the first
        // attempt here: the holder's width is 0 until layout runs, so the knob
        // computed a NEGATIVE implicitHeight at creation and then visibly grew
        // into place one frame later, every time a switch was instantiated —
        // because the Behaviors below were already live. The slot's implicit
        // sizes are literal expressions, available immediately, so they have no
        // such transient. Radius still comes from the knob itself.
        PillSurface {
            id: knob

            readonly property real nonAnimWidth: root.pressed ? knob.implicitHeight * 1.3 : knob.implicitHeight

            color: root._knobStyle.background
            borderColor: root._knobStyle.border
            // ON is polished, OFF is stock machined face. This is what carries
            // "whiter" — the body lift alone would only make it a paler grey.
            //
            // The swap is INSTANT while the body colour cross-fades, so the
            // finish technically pops mid-transition. Left that way on purpose:
            // cross-fading two stacked SurfaceFinishes would composite both
            // sweeps at the midpoint and overshoot the brightness that was
            // tuned by eye, and on this control the knob's travel dominates the
            // transition anyway.
            finishRecipe: root.checked ? Theme.engaged : Theme.pill

            x: root.checked ? slot.implicitWidth - nonAnimWidth - Appearance.padding.small / 2 : Appearance.padding.small / 2
            implicitWidth: nonAnimWidth
            implicitHeight: slot.implicitHeight - Appearance.padding.small
            anchors.verticalCenter: parent.verticalCenter

            StyledRect {
                anchors.fill: parent
                radius: knob.radius

                color: Colours.palette.m3onSurface
                opacity: root.pressed ? 0.1 : root.hovered ? 0.08 : 0

                Behavior on opacity {
                    Anim {}
                }
            }

            Behavior on x {
                Anim {}
            }

            Behavior on implicitWidth {
                Anim {}
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: false
    }
}
