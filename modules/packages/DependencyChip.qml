import qs.components
import qs.services
import qs.config
import QtQuick

/// Small pill-shaped chip for displaying a dependency name.
///
/// Clicking navigates back to search with the dependency name as query,
/// allowing users to explore the dependency tree interactively.
StyledRect {
    id: root

    required property string depName

    color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
    radius: Appearance.rounding.full

    implicitWidth: label.implicitWidth + Appearance.padding.normal * 2
    implicitHeight: label.implicitHeight + Appearance.padding.small * 2

    StyledText {
        id: label

        anchors.centerIn: parent
        text: root.depName
        font.pointSize: Appearance.font.size.small
        font.family: "monospace"
        color: Colours.palette.m3primary
    }

    StateLayer {
        radius: root.radius
        color: Colours.palette.m3primary

        function onClicked(): void {
            Packages.searchFromDetail(root.depName);
        }
    }
}
