pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Shared header row for the dashboard utility cards (Keep Awake, Schedule
// Suspend): a state-brightened icon pill, a title/subtitle column, and a
// StyledSwitch. `active` drives BOTH the icon-pill brightening and the
// switch's checked state — both cards keep those in lockstep — while the
// card owns the on/off action via the toggled(checked) signal.
//
// The root is a bare RowLayout so a card can either anchor it (Keep Awake
// anchors the header directly to the PillCard) or drop it into a ColumnLayout
// (Schedule Suspend stacks it above its swap area). Margins belong to the
// consumer's context, not here.
RowLayout {
    id: root

    required property string icon
    required property string title
    property string subtitle: ""
    property bool active: false

    signal toggled(bool checked)

    Layout.fillWidth: true
    spacing: Appearance.spacing.normal

    PillSurface {
        implicitWidth: implicitHeight
        implicitHeight: iconLabel.implicitHeight + Appearance.padding.smaller * 2

        // Brighten the body when active, but keep the raised claymorphism depth
        // in both states so the icon circle reads as part of the same pill
        // family as the Quick Toggles below.
        color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, root.active ? Colours.glass.veryStrong : Colours.glass.subtle).background

        MaterialIcon {
            id: iconLabel

            anchors.centerIn: parent
            text: root.icon
            color: Colours.palette.m3onSurface
            font.pointSize: Appearance.font.size.large
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pointSize: Appearance.font.size.normal
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            text: root.subtitle
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.small
            elide: Text.ElideRight
        }
    }

    StyledSwitch {
        checked: root.active
        onToggled: root.toggled(checked)
    }
}
