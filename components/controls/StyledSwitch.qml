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
// range while the slot sits near the bottom: slot #0e0f10, OFF knob body
// #1a1c1d, its border #242526 — roughly 12 levels of body separation carried by
// a 36-level edge. ON is where the contrast budget was spent instead: body
// #958d7d against the same #0e0f10 slot, plus the polished finish on top.
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
// Under clay the same structure degrades to a raised neumorphic knob in a well,
// which is the classic clay form.
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
        active: true
        activeColor: root._slotStyle.background
        borderColor: root._slotStyle.border

        implicitWidth: implicitHeight * 1.7
        implicitHeight: Appearance.font.size.normal + Appearance.padding.smaller * 2

        // NOTE on `parent` in this scope: PillToggleSurface reparents its
        // default-slot children into an internal content holder that is
        // anchors.fill'd, so it has a real width/height but NO implicitWidth /
        // implicitHeight and no radius. Read parent.width/parent.height, and
        // take the radius from the knob itself.
        PillSurface {
            id: knob

            readonly property real nonAnimWidth: root.pressed ? implicitHeight * 1.3 : implicitHeight

            color: root._knobStyle.background
            borderColor: root._knobStyle.border
            // ON is polished, OFF is stock machined face. This is what carries
            // "whiter" — the body lift alone would only make it a paler grey.
            finishRecipe: root.checked ? Theme.engaged : Theme.pill

            x: root.checked ? parent.width - nonAnimWidth - Appearance.padding.small / 2 : Appearance.padding.small / 2
            implicitWidth: nonAnimWidth
            implicitHeight: parent.height - Appearance.padding.small
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
