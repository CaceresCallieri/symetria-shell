pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Single power-profile toggle pill — neumorphic depress/raise carries state,
// monochrome (no accent fill) to match the shell-wide toggle language used
// in QuickToggles (see IconButton.qml: activeColour returns inactiveColour
// for toggle-style buttons). Used by the Battery popout and the dedicated
// PowerProfile popout.
PillToggleSurface {
    id: pill

    required property string icon
    required property int profile

    readonly property bool selected: PowerProfiles.profile === profile

    Layout.fillWidth: true
    implicitHeight: pillIcon.implicitHeight + Appearance.padding.normal * 2

    active: selected
    activeColor: inactiveColor // Same color — neumorphic toggle; state signaled by inset shadow, not fill

    StateLayer {
        color: Colours.palette.m3onSurface

        function onClicked(): void {
            PowerProfiles.profile = pill.profile;
        }
    }

    MaterialIcon {
        id: pillIcon

        anchors.centerIn: parent
        text: pill.icon
        font.pointSize: Appearance.font.size.large
        color: Colours.palette.m3onSurface
        fill: pill.selected ? 1 : 0

        Behavior on fill {
            Anim {}
        }
    }
}
