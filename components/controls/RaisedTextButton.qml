import ".."
import qs.services
import qs.config
import QtQuick

// Text-only action button with the raised dark-neumorphism pill treatment —
// the same visual as the utilities Quick Toggles in their inactive state
// (PillToggleSurface, raised). No icon, no toggle state: a pure action.
//
// This is the intended DEFAULT button style for the shell going forward;
// prefer it over PillButton/TextButton for new action buttons.
PillToggleSurface {
    id: root

    property alias text: label.text
    property alias font: label.font
    property bool disabled: false
    property real horizontalPadding: Appearance.padding.large
    property real verticalPadding: Appearance.padding.smaller

    signal clicked()

    raised: true
    active: false
    radius: Appearance.rounding.normal

    implicitWidth: label.implicitWidth + horizontalPadding * 2
    implicitHeight: label.implicitHeight + verticalPadding * 2

    StateLayer {
        color: Colours.palette.m3onSurface
        disabled: root.disabled

        function onClicked(): void {
            root.clicked();
        }
    }

    StyledText {
        id: label

        anchors.centerIn: parent
        color: root.disabled ? Qt.alpha(Colours.palette.m3onSurface, 0.38) : Colours.palette.m3onSurface
    }
}
