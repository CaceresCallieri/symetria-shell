import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

Item {
    id: root

    required property PersistentProperties visibilities

    implicitWidth: powerGlyph.implicitHeight + Appearance.padding.small * 2
    implicitHeight: powerGlyph.implicitHeight

    StateLayer {
        // Cursed workaround to make the height larger than the parent
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: powerGlyph.implicitHeight + Appearance.padding.small * 2

        radius: Appearance.rounding.full

        function onClicked(): void {
            root.visibilities.session = !root.visibilities.session;
        }
    }

    BarIcon {
        id: powerGlyph

        anchors.centerIn: parent

        icon: "power_settings_new"
        tint: Colours.palette.m3powerButton
    }
}
