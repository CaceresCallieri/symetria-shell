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

    // Bar-icon size, not the old `normal` + bold: Phosphor Light has one
    // weight, and at `normal` its hairline reads smaller than the status
    // glyphs beside it. The old -1 offset centred Material's glyph; Phosphor's
    // power glyph is drawn centred. The hit area follows from implicitHeight.
    BarIcon {
        id: powerGlyph

        anchors.centerIn: parent

        icon: "power_settings_new"
        tint: Colours.palette.m3powerButton
    }
}
