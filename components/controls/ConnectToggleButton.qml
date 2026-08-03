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

    // Shared by the socket and the hover/ripple layer. Bound to the FORM axis
    // like every other surface, so `form: panel` squares this off with the rest
    // of the shell instead of leaving one stray capsule.
    readonly property real radius: Appearance.rounding.full * Theme.layout.surfaceRounding

    implicitWidth: implicitHeight
    // SIZE NOTE: the six call sites this replaced did not agree. The three
    // control-center lists used `padding.smaller * 2` (14); the three bar
    // popouts used a bare `padding.small` (5, not doubled), so their rows were
    // ~9px shorter. Unifying on the larger value is deliberate — one control
    // should not be two sizes depending on which panel it is in, and the larger
    // one is the better pointer target — but it does mean the bar popout rows
    // grew. Expose a per-instance override here rather than reverting if a
    // caller ever needs the compact form back.
    implicitHeight: icon.implicitHeight + Appearance.padding.smaller * 2

    // `active: true` unconditionally: this is a recess, and a recess is a
    // recess in both states. The STATE is whether the recess exists at all,
    // which `opacity` decides. Binding `active` to `connected` instead would
    // animate the inset gradient in from a raised plate that is never seen.
    PillToggleSurface {
        id: socket

        anchors.fill: parent
        active: true
        // Polished accent metal — m3primary is chromatic enough to cross
        // metalPill()'s accentSaturationThreshold, so it keeps the palette's
        // warm hue instead of collapsing to neutral near-black the way a
        // surface container would, and engagedPillStyle then lifts it past the
        // material's ceiling. Both colours come from the one cached accessor:
        // background and border must originate in the SAME call or the edge
        // stops matching the face.
        activeColor: Colours.engagedAccent.background
        borderColor: Colours.engagedAccent.border

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

    // Behind a Loader, not instantiated unconditionally: CircularIndicator is a
    // BusyIndicator whose contentItem is Shape-based and which owns two
    // NumberAnimations. This component is a delegate in the wireless list,
    // which routinely holds 20-40 scanned networks — and two of the six call
    // sites it replaced had no indicator at all, so an always-on one would be
    // pure new cost on every control-center open.
    //
    // Transparent track: the indicator replaces the icon in place, and a filled
    // track would draw a disc on the rows that have no socket.
    Loader {
        anchors.fill: parent
        active: root.loading

        sourceComponent: CircularIndicator {
            running: true
            bgColour: "transparent"
        }
    }

    // Last, so it takes input above the socket and the icon. The radius is
    // bound explicitly rather than left to StateLayer's `parent?.radius ?? 0`
    // default: that default WOULD resolve correctly here, since root declares
    // `radius` above, but only by coincidence of this file's shape. Stating it
    // keeps the ripple's clipping independent of whether a future refactor
    // moves the StateLayer inside something that reparents. See the
    // parent-radius entry in docs/qml-pitfalls.md.
    StateLayer {
        radius: root.radius
        color: Colours.palette.m3onSurface
        disabled: root.loading || root.disabled

        function onClicked(): void {
            root.clicked();
        }
    }
}
