pragma ComponentBehavior: Bound

import ".."
import qs.services
import qs.config
import QtQuick

// The connect / disconnect action at the end of a network or device row.
//
// WHY THIS IS A COMPONENT: this control was open-coded at six call sites (wifi
// and ethernet in the bar's network popout, the bluetooth popout, and the three
// control-center lists) and had already drifted into two incompatible dialects.
// The control-center copies routed their connected fill through
// Colours.pillStyle(), so they followed the active material. The bar-popout
// copies filled with `Qt.alpha(m3primary, 1)` — a raw palette colour no
// material ever sees. That is why the connected row in the wifi popout read as
// a pale disc pasted onto a machined panel: it was not styled by the theme at
// all. Six copies of one control is also how the next divergence happens, so
// they all route through here now.
//
// THE STATE VOCABULARY: connected is drawn as a SOCKET, not as a lamp.
// Material Design encodes "active" as a brighter fill. A machined surface has
// no such affordance — polished metal does not emit — so this shell encodes it
// as ACTUATED: the part sits INTO the panel and stops catching the light, and
// takes a warm tint from the accent. That is already how every
// PillToggleSurface in the shell signals "on" (see the recipe comments in
// services/Theme.qml); this control joins that convention rather than
// inventing a third one. Reading it literally: the cable is plugged in.
//
// Disconnected draws no plate at all — a dozen network rows each carrying a
// plate is noise, and the plate APPEARING is the state. It fades rather than
// pops so a connect reads as the socket seating, not as a new element.
Item {
    id: root

    property bool connected: false
    property bool loading: false
    property bool disabled: false

    signal clicked

    // Polished accent metal. m3primary is chromatic enough to cross
    // metalPill()'s accentSaturationThreshold, so this takes the accent path
    // and keeps the palette's warm hue instead of collapsing to neutral
    // near-black like a surface container would; engagedPillStyle then lifts it
    // past the material's ceiling, which is what a connected part has earned
    // and a container has not. Cached once — background and border must come
    // from the SAME call or the edge stops matching the face.
    readonly property var _socketStyle: Colours.engagedPillStyle(Colours.palette.m3primary, Colours.glass.strong, Colours.polish.standard)

    // Shared by the socket and the hover/ripple layer. Bound to the FORM axis
    // like every other surface, so `form: panel` squares this off with the rest
    // of the shell instead of leaving one stray capsule.
    readonly property real radius: Appearance.rounding.full * Theme.layout.surfaceRounding

    implicitWidth: implicitHeight
    implicitHeight: icon.implicitHeight + Appearance.padding.smaller * 2

    // `active: true` unconditionally: this is a recess, and a recess is a
    // recess in both states. The STATE is whether the recess exists at all,
    // which `opacity` decides. Binding `active` to `connected` instead would
    // animate the inset gradient in from a raised plate that is never seen.
    PillToggleSurface {
        id: socket

        anchors.fill: parent
        active: true
        activeColor: root._socketStyle.background
        borderColor: root._socketStyle.border

        // Inset AND polished. `active: true` drives specularFactor to 0 by
        // default, which left this a flat warm swatch with no highlight at all;
        // the override restores the lit layers so the socket lip catches light.
        finishRecipe: Theme.engaged
        specularFactor: 1

        opacity: root.connected ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {}
        }
    }

    // Declared OUTSIDE the socket rather than in its content slot: the icon
    // must stay put while the socket fades in and out, and PillToggleSurface
    // clips its slot to the pill body.
    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        text: root.connected ? "link_off" : "link"
        // ONE colour for both states, deliberately. The icon used to warm up to
        // m3primary when connected, which made sense against a dim socket; on
        // the lifted one it would be a warm glyph on a warm plate and would lose
        // contrast exactly where legibility matters most. The socket carries the
        // state now, and the glyph itself already changes shape.
        color: Colours.palette.m3onSurface

        opacity: root.loading ? 0 : 1

        Behavior on opacity {
            Anim {}
        }
    }

    // Transparent track: the indicator replaces the icon in place, and a filled
    // track would draw a disc on the rows that have no socket.
    CircularIndicator {
        anchors.fill: parent
        running: root.loading
        bgColour: "transparent"
    }

    // Last, so it takes input above the socket and the icon. Explicit radius —
    // StateLayer's default reads `parent.radius`, and `parent` here is a plain
    // Item, so the ripple would clip to a square. See docs/qml-pitfalls.md.
    StateLayer {
        radius: root.radius
        color: Colours.palette.m3onSurface
        disabled: root.loading || root.disabled

        function onClicked(): void {
            root.clicked();
        }
    }
}
