pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Single power-mode toggle pill — a pure view of one PowerMode entry. Neumorphic
// depress/raise carries state, monochrome (no accent fill) to match the
// shell-wide toggle language used in QuickToggles (see IconButton.qml:
// activeColour returns inactiveColour for toggle-style buttons). All mode
// semantics (which is active, what clicking does) live in PowerMode, so this
// stays a dumb delegate — drive it from PowerMode.modes via a Repeater.
PillToggleSurface {
    id: pill

    // One entry from PowerMode.modes ({ silent, profile, icon, label }).
    required property var mode

    readonly property bool selected: PowerMode.isActive(pill.mode)

    Layout.fillWidth: true
    implicitHeight: pillIcon.implicitHeight + Appearance.padding.normal * 2

    active: selected
    activeColor: inactiveColor // Same color — neumorphic toggle; state signaled by inset shadow, not fill

    StateLayer {
        color: Colours.palette.m3onSurface

        function onClicked(): void {
            PowerMode.apply(pill.mode);
        }
    }

    MaterialIcon {
        id: pillIcon

        anchors.centerIn: parent
        text: pill.mode.icon
        font.pointSize: Appearance.font.size.large
        color: Colours.palette.m3onSurface
        fill: pill.selected ? 1 : 0

        Behavior on fill {
            Anim {}
        }
    }
}
