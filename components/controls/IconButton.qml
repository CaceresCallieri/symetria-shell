import ".."
import qs.services
import qs.config
import QtQuick

StyledRect {
    id: root

    enum Type {
        Filled,
        Tonal,
        Text
    }

    property alias icon: label.text
    property bool checked
    property bool toggle
    property real padding: type === IconButton.Text ? Appearance.padding.small / 2 : Appearance.padding.smaller
    property alias font: label.font
    property int type: IconButton.Filled
    property bool disabled
    property bool loading: false

    property alias stateLayer: stateLayer
    property alias label: label
    property alias radiusAnim: radiusAnim

    property bool internalChecked
    property color activeColour: Qt.lighter(Colours.pillStyle(type === IconButton.Filled ? Colours.palette.m3primary : Colours.palette.m3secondary, Colours.glass.veryStrong).background, 1.5)
    property color inactiveColour: {
        if (!toggle && type === IconButton.Filled)
            return Qt.lighter(Colours.pillStyle(Colours.palette.m3primary, Colours.glass.veryStrong).background, 1.5);
        return type === IconButton.Filled ? Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background : Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background;
    }
    property color activeOnColour: type === IconButton.Text ? Colours.palette.m3primary : Colours.palette.m3onSurface
    property color inactiveOnColour: {
        if (!toggle && type === IconButton.Filled)
            return Colours.palette.m3onSurface;
        return type === IconButton.Text ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface;
    }
    property color disabledColour: Qt.alpha(Colours.palette.m3onSurface, 0.1)
    property color disabledOnColour: Qt.alpha(Colours.palette.m3onSurface, 0.38)

    signal clicked

    onCheckedChanged: internalChecked = checked

    radius: internalChecked ? Appearance.rounding.small : implicitHeight / 2 * Math.min(1, Appearance.rounding.scale)
    color: type === IconButton.Text ? "transparent" : disabled ? disabledColour : internalChecked ? activeColour : inactiveColour

    implicitWidth: implicitHeight
    implicitHeight: label.implicitHeight + padding * 2

    StateLayer {
        id: stateLayer

        color: root.internalChecked ? root.activeOnColour : root.inactiveOnColour
        disabled: root.disabled

        function onClicked(): void {
            if (root.toggle)
                root.internalChecked = !root.internalChecked;
            root.clicked();
        }
    }

    Item {
        anchors.centerIn: parent
        implicitWidth: label.implicitWidth
        implicitHeight: label.implicitHeight

        MaterialIcon {
            id: label

            anchors.centerIn: parent
            color: root.disabled ? root.disabledOnColour : root.internalChecked ? root.activeOnColour : root.inactiveOnColour
            fill: !root.toggle || root.internalChecked ? 1 : 0
            opacity: root.loading ? 0 : 1

            Behavior on fill {
                Anim {}
            }

            Behavior on opacity {
                Anim {}
            }
        }

        Loader {
            anchors.centerIn: parent
            active: root.loading
            sourceComponent: CircularIndicator {
                implicitSize: label.implicitHeight
                strokeWidth: Appearance.padding.small * 0.5
                fgColour: root.internalChecked ? root.activeOnColour : root.inactiveOnColour
                bgColour: Qt.alpha(fgColour, 0.3)
                running: true
            }
        }
    }

    Behavior on radius {
        Anim {
            id: radiusAnim
        }
    }
}
