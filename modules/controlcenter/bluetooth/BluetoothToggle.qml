pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.config
import QtQuick.Layouts

/// Bluetooth toggle row: label + switch.
/// Shared by Details.qml and Settings.qml.
RowLayout {
    id: root

    required property string label
    property alias checked: toggle.checked
    property alias toggle: toggle

    Layout.fillWidth: true
    spacing: Appearance.spacing.normal

    StyledText {
        Layout.fillWidth: true
        text: root.label
    }

    StyledSwitch {
        id: toggle

        cLayer: 2
    }
}
