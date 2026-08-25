import ".."
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Icon + text action button with the raised dark-neumorphism pill treatment —
// the icon-bearing sibling of RaisedTextButton (same PillToggleSurface raised
// claymorphism as the utilities Quick Toggles' inactive state). A pure action,
// no toggle. Use when an action button wants the raised pill look AND a leading
// icon; use RaisedTextButton when no icon is needed.
PillToggleSurface {
    id: root

    property alias icon: iconLabel.text
    property alias text: label.text
    property alias font: label.font
    property bool disabled: false
    // Foreground (icon + label) colour. Defaults to the neutral on-surface role
    // so it reads identically to RaisedTextButton; override for emphasis.
    property color contentColour: Colours.palette.m3onSurface
    property real horizontalPadding: Appearance.padding.large
    property real verticalPadding: Appearance.padding.smaller
    property real spacing: Appearance.spacing.small

    signal clicked

    raised: true
    active: false
    radius: Appearance.rounding.normal

    implicitWidth: row.implicitWidth + horizontalPadding * 2
    implicitHeight: row.implicitHeight + verticalPadding * 2

    StateLayer {
        color: root.contentColour
        disabled: root.disabled

        function onClicked(): void {
            root.clicked();
        }
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: root.spacing

        MaterialIcon {
            id: iconLabel

            Layout.alignment: Qt.AlignVCenter
            color: root.disabled ? Qt.alpha(root.contentColour, 0.38) : root.contentColour
        }

        StyledText {
            id: label

            Layout.alignment: Qt.AlignVCenter
            color: root.disabled ? Qt.alpha(root.contentColour, 0.38) : root.contentColour
        }
    }
}
