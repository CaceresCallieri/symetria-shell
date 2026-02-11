import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Reusable collapsible section for the package detail view.
///
/// Provides a section title with consistent styling, and a default
/// content slot below it. Follows the Bluetooth Details section pattern.
ColumnLayout {
    id: root

    required property string title
    default property alias content: contentColumn.children

    spacing: Appearance.spacing.normal

    StyledText {
        Layout.topMargin: Appearance.spacing.large
        text: root.title
        font.pointSize: Appearance.font.size.larger
        font.weight: 500
    }

    ColumnLayout {
        id: contentColumn

        Layout.fillWidth: true
        spacing: Appearance.spacing.small
    }
}
