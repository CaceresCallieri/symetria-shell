import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

PillCard {
    id: root

    // Spacing between the main layout row and the active-since chip below it.
    readonly property real chipTopSpacing: Appearance.spacing.larger

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + (IdleInhibitor.enabled ? activeChip.implicitHeight + root.chipTopSpacing : 0) + Appearance.padding.large * 2

    // Opt into clipping: the active-since chip slides off the bottom edge
    // when Keep Awake is toggled off, and we want that overflow hidden.
    clipContent: true

    UtilityCardHeader {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Appearance.padding.large

        icon: "coffee"
        title: qsTr("Keep Awake")
        subtitle: IdleInhibitor.enabled ? qsTr("Preventing sleep mode") : qsTr("Normal power management")
        active: IdleInhibitor.enabled
        onToggled: checked => IdleInhibitor.enabled = checked
    }

    Loader {
        id: activeChip

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: IdleInhibitor.enabled ? Appearance.padding.large : -implicitHeight
        anchors.leftMargin: Appearance.padding.large

        opacity: IdleInhibitor.enabled ? 1 : 0
        scale: IdleInhibitor.enabled ? 1 : 0.5

        Component.onCompleted: active = Qt.binding(() => opacity > 0)

        sourceComponent: StyledRect {
            implicitWidth: activeText.implicitWidth + Appearance.padding.normal * 2
            implicitHeight: activeText.implicitHeight + Appearance.padding.small * 2

            radius: Appearance.rounding.full
            color: Colours.palette.m3primary

            StyledText {
                id: activeText

                anchors.centerIn: parent
                text: qsTr("Active since %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, Config.services.useTwelveHourClock ? "hh:mm a" : "hh:mm"))
                color: Colours.palette.m3onPrimary
                font.pointSize: Math.round(Appearance.font.size.small * 0.9)
            }
        }

        Behavior on anchors.bottomMargin {
            Anim {
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        }

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitHeight {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
    }
}
