import qs.components
import qs.components.effects
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

StyledRect {
    id: root

    default property alias content: contentColumn.data
    property real contentSpacing: Appearance.spacing.larger
    property bool alignTop: false

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight + Appearance.padding.large * 2

    readonly property var pill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.medium) // intentional var: heterogeneous JS { background, border }

    radius: Appearance.rounding.normal
    color: pill.background
    border.color: pill.border
    border.width: 1

    ColumnLayout {
        id: contentColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.alignTop ? parent.top : undefined
        anchors.verticalCenter: root.alignTop ? undefined : parent.verticalCenter
        anchors.margins: Appearance.padding.large

        spacing: root.contentSpacing
    }
}

