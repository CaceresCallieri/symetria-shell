import ".."
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

Row {
    id: root

    enum Type {
        Filled,
        Tonal
    }

    property real horizontalPadding: Appearance.padding.normal
    property real verticalPadding: Appearance.padding.smaller
    property int type: SplitButton.Filled
    property bool disabled
    property bool loading
    property bool menuOnTop
    property string fallbackIcon
    property string fallbackText

    property alias menuItems: menu.items
    property alias active: menu.active
    property alias expanded: menu.expanded
    property alias menu: menu
    property alias iconLabel: iconLabel
    property alias label: label
    property alias stateLayer: stateLayer

    property color colour: type == SplitButton.Filled ? Qt.lighter(Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.medium).background, 1.5) : Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background
    property color textColour: Colours.palette.m3onSurface
    property color disabledColour: Qt.alpha(Colours.palette.m3onSurface, 0.1)
    property color disabledTextColour: Qt.alpha(Colours.palette.m3onSurface, 0.38)

    spacing: Math.floor(Appearance.spacing.small / 2)

    StyledRect {
        radius: implicitHeight / 2 * Math.min(1, Appearance.rounding.scale)
        topRightRadius: Appearance.rounding.small / 2
        bottomRightRadius: Appearance.rounding.small / 2
        color: root.disabled ? root.disabledColour : root.colour

        implicitWidth: textRow.implicitWidth + root.horizontalPadding * 2
        implicitHeight: expandBtn.implicitHeight

        StateLayer {
            id: stateLayer

            rect.topRightRadius: parent.topRightRadius
            rect.bottomRightRadius: parent.bottomRightRadius
            color: root.textColour
            disabled: root.disabled

            function onClicked(): void {
                root.active?.clicked();
            }
        }

        RowLayout {
            id: textRow

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: Math.floor(root.verticalPadding / 4)
            spacing: Appearance.spacing.small

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: iconLabel.implicitWidth
                implicitHeight: iconLabel.implicitHeight

                MaterialIcon {
                    id: iconLabel

                    anchors.centerIn: parent
                    animate: true
                    text: root.active?.activeIcon ?? root.fallbackIcon
                    color: root.disabled ? root.disabledTextColour : root.textColour
                    fill: 1
                    opacity: root.loading ? 0 : 1

                    Behavior on opacity {
                        Anim {}
                    }
                }

                Loader {
                    anchors.centerIn: parent
                    active: root.loading
                    sourceComponent: CircularIndicator {
                        implicitSize: iconLabel.implicitHeight
                        strokeWidth: Appearance.padding.small * 0.5
                        fgColour: Colours.palette.m3onSurface
                        bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.3)
                        running: true
                    }
                }
            }

            StyledText {
                id: label

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: implicitWidth
                animate: true
                text: root.active?.activeText ?? root.fallbackText
                color: root.disabled ? root.disabledTextColour : root.textColour
                clip: true

                Behavior on Layout.preferredWidth {
                    Anim {
                        easing.bezierCurve: Appearance.anim.curves.emphasized
                    }
                }
            }
        }
    }

    StyledRect {
        id: expandBtn

        property real rad: root.expanded ? implicitHeight / 2 * Math.min(1, Appearance.rounding.scale) : Appearance.rounding.small / 2

        radius: implicitHeight / 2 * Math.min(1, Appearance.rounding.scale)
        topLeftRadius: rad
        bottomLeftRadius: rad
        color: root.disabled ? root.disabledColour : root.colour

        implicitWidth: implicitHeight
        implicitHeight: expandIcon.implicitHeight + root.verticalPadding * 2

        StateLayer {
            id: expandStateLayer

            rect.topLeftRadius: parent.topLeftRadius
            rect.bottomLeftRadius: parent.bottomLeftRadius
            color: root.textColour
            disabled: root.disabled

            function onClicked(): void {
                root.expanded = !root.expanded;
            }
        }

        MaterialIcon {
            id: expandIcon

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.expanded ? 0 : -Math.floor(root.verticalPadding / 4)

            text: "expand_more"
            color: root.disabled ? root.disabledTextColour : root.textColour
            rotation: root.expanded ? 180 : 0

            Behavior on anchors.horizontalCenterOffset {
                Anim {}
            }

            Behavior on rotation {
                Anim {}
            }
        }

        Behavior on rad {
            Anim {}
        }

        Menu {
            id: menu

            states: State {
                when: root.menuOnTop

                AnchorChanges {
                    target: menu
                    anchors.top: undefined
                    anchors.bottom: expandBtn.top
                }
            }

            anchors.top: parent.bottom
            anchors.right: parent.right
            anchors.topMargin: Appearance.spacing.small
            anchors.bottomMargin: Appearance.spacing.small
        }
    }
}
