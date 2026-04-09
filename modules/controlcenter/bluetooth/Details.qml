pragma ComponentBehavior: Bound

import ".."
import "../components"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import qs.utils
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

StyledFlickable {
    id: root

    required property Session session
    readonly property BluetoothDevice device: session.bt.active

    flickableDirection: Flickable.VerticalFlick
    contentHeight: detailsWrapper.height

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    Item {
        id: detailsWrapper

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: details.implicitHeight

        DeviceDetails {
            id: details

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            session: root.session
            device: root.device

            headerComponent: Component {
                SettingsHeader {
                    icon: Icons.getBluetoothIcon(root.device?.icon ?? "")
                    title: root.device?.name ?? ""
                }
            }

            sections: [
                Component {
                    ColumnLayout {
                        spacing: Appearance.spacing.normal

                        StyledText {
                            Layout.topMargin: Appearance.spacing.large
                            text: qsTr("Connection status")
                            font.pointSize: Appearance.font.size.larger
                            font.weight: 500
                        }

                        StyledText {
                            text: qsTr("Connection settings for this device")
                            color: Colours.palette.m3outline
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: deviceStatus.implicitHeight + Appearance.padding.large * 2

                            readonly property var pill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle) // intentional var: heterogeneous JS { background, border }

                            radius: Appearance.rounding.normal
                            color: pill.background
                            border.color: pill.border
                            border.width: 1

                            ColumnLayout {
                                id: deviceStatus

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Appearance.padding.large

                                spacing: Appearance.spacing.larger

                                BluetoothToggle {
                                    label: qsTr("Connected")
                                    checked: root.device?.connected ?? false
                                    toggle.onToggled: root.device.connected = checked
                                }

                                BluetoothToggle {
                                    label: qsTr("Paired")
                                    checked: root.device?.paired ?? false
                                    toggle.onToggled: {
                                        if (root.device.paired)
                                            root.device.forget();
                                        else
                                            root.device.pair();
                                    }
                                }

                                BluetoothToggle {
                                    label: qsTr("Blocked")
                                    checked: root.device?.blocked ?? false
                                    toggle.onToggled: root.device.blocked = checked
                                }
                            }
                        }
                    }
                },
                Component {
                    ColumnLayout {
                        spacing: Appearance.spacing.normal

                        StyledText {
                            Layout.topMargin: Appearance.spacing.large
                            text: qsTr("Device properties")
                            font.pointSize: Appearance.font.size.larger
                            font.weight: 500
                        }

                        StyledText {
                            text: qsTr("Additional settings")
                            color: Colours.palette.m3outline
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: deviceProps.implicitHeight + Appearance.padding.large * 2

                            readonly property var pill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle) // intentional var: heterogeneous JS { background, border }

                            radius: Appearance.rounding.normal
                            color: pill.background
                            border.color: pill.border
                            border.width: 1

                            ColumnLayout {
                                id: deviceProps

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Appearance.padding.large

                                spacing: Appearance.spacing.larger

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.small

                                    Item {
                                        id: renameDevice

                                        Layout.fillWidth: true
                                        Layout.rightMargin: Appearance.spacing.small

                                        implicitHeight: renameLabel.implicitHeight + deviceNameEdit.implicitHeight

                                        states: State {
                                            name: "editingDeviceName"
                                            when: root.session.bt.editingDeviceName

                                            AnchorChanges {
                                                target: deviceNameEdit
                                                anchors.top: renameDevice.top
                                            }
                                            PropertyChanges {
                                                renameDevice.implicitHeight: deviceNameEdit.implicitHeight
                                                renameLabel.opacity: 0
                                                deviceNameEdit.padding: Appearance.padding.normal
                                            }
                                        }

                                        transitions: Transition {
                                            AnchorAnimation {
                                                duration: Appearance.anim.durations.normal
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Appearance.anim.curves.standard
                                            }
                                            Anim {
                                                properties: "implicitHeight,opacity,padding"
                                            }
                                        }

                                        StyledText {
                                            id: renameLabel

                                            anchors.left: parent.left

                                            text: qsTr("Device name")
                                            color: Colours.palette.m3outline
                                            font.pointSize: Appearance.font.size.small
                                        }

                                        StyledTextField {
                                            id: deviceNameEdit

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: renameLabel.bottom
                                            anchors.leftMargin: root.session.bt.editingDeviceName ? 0 : -Appearance.padding.normal

                                            text: root.device?.name ?? ""
                                            readOnly: !root.session.bt.editingDeviceName
                                            onAccepted: {
                                                root.session.bt.editingDeviceName = false;
                                                root.device.name = text;
                                            }

                                            leftPadding: Appearance.padding.normal
                                            rightPadding: Appearance.padding.normal

                                            background: StyledRect {
                                                radius: Appearance.rounding.small
                                                border.width: 2
                                                border.color: Colours.palette.m3primary
                                                opacity: root.session.bt.editingDeviceName ? 1 : 0

                                                Behavior on border.color {
                                                    CAnim {}
                                                }

                                                Behavior on opacity {
                                                    Anim {}
                                                }
                                            }

                                            Behavior on anchors.leftMargin {
                                                Anim {}
                                            }
                                        }
                                    }

                                    StyledRect {
                                        implicitWidth: implicitHeight
                                        implicitHeight: cancelEditIcon.implicitHeight + Appearance.padding.smaller * 2

                                        radius: Appearance.rounding.small
                                        color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background
                                        opacity: root.session.bt.editingDeviceName ? 1 : 0
                                        scale: root.session.bt.editingDeviceName ? 1 : 0.5

                                        StateLayer {
                                            color: Colours.palette.m3onSurface
                                            disabled: !root.session.bt.editingDeviceName

                                            function onClicked(): void {
                                                root.session.bt.editingDeviceName = false;
                                                deviceNameEdit.text = Qt.binding(() => root.device?.name ?? "");
                                            }
                                        }

                                        MaterialIcon {
                                            id: cancelEditIcon

                                            anchors.centerIn: parent
                                            animate: true
                                            text: "cancel"
                                            color: Colours.palette.m3onSurface
                                        }

                                        Behavior on opacity {
                                            Anim {}
                                        }

                                        Behavior on scale {
                                            Anim {
                                                duration: Appearance.anim.durations.expressiveFastSpatial
                                                easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
                                            }
                                        }
                                    }

                                    StyledRect {
                                        implicitWidth: implicitHeight
                                        implicitHeight: editIcon.implicitHeight + Appearance.padding.smaller * 2

                                        radius: root.session.bt.editingDeviceName ? Appearance.rounding.small : implicitHeight / 2 * Math.min(1, Appearance.rounding.scale)
                                        color: Qt.alpha(Colours.palette.m3primary, root.session.bt.editingDeviceName ? 1 : 0)

                                        StateLayer {
                                            color: root.session.bt.editingDeviceName ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

                                            function onClicked(): void {
                                                root.session.bt.editingDeviceName = !root.session.bt.editingDeviceName;
                                                if (root.session.bt.editingDeviceName)
                                                    deviceNameEdit.forceActiveFocus();
                                                else
                                                    deviceNameEdit.accepted();
                                            }
                                        }

                                        MaterialIcon {
                                            id: editIcon

                                            anchors.centerIn: parent
                                            animate: true
                                            text: root.session.bt.editingDeviceName ? "check_circle" : "edit"
                                            color: root.session.bt.editingDeviceName ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                        }

                                        Behavior on radius {
                                            Anim {}
                                        }
                                    }
                                }

                                BluetoothToggle {
                                    label: qsTr("Trusted")
                                    checked: root.device?.trusted ?? false
                                    toggle.onToggled: root.device.trusted = checked
                                }

                                BluetoothToggle {
                                    label: qsTr("Wake allowed")
                                    checked: root.device?.wakeAllowed ?? false
                                    toggle.onToggled: root.device.wakeAllowed = checked
                                }
                            }
                        }
                    }
                },
                Component {
                    ColumnLayout {
                        spacing: Appearance.spacing.normal

                        StyledText {
                            Layout.topMargin: Appearance.spacing.large
                            text: qsTr("Device information")
                            font.pointSize: Appearance.font.size.larger
                            font.weight: 500
                        }

                        StyledText {
                            text: qsTr("Information about this device")
                            color: Colours.palette.m3outline
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: deviceInfo.implicitHeight + Appearance.padding.large * 2

                            readonly property var pill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle) // intentional var: heterogeneous JS { background, border }

                            radius: Appearance.rounding.normal
                            color: pill.background
                            border.color: pill.border
                            border.width: 1

                            ColumnLayout {
                                id: deviceInfo

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Appearance.padding.large

                                spacing: Appearance.spacing.small / 2

                                StyledText {
                                    text: root.device?.batteryAvailable ? qsTr("Device battery (%1%)").arg(root.device.battery * 100) : qsTr("Battery unavailable")
                                }

                                RowLayout {
                                    Layout.topMargin: Appearance.spacing.small / 2
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Appearance.padding.smaller
                                    spacing: Appearance.spacing.small / 2

                                    StyledRect {
                                        Layout.fillHeight: true
                                        implicitWidth: root.device?.batteryAvailable ? parent.width * root.device.battery : 0
                                        radius: Appearance.rounding.full
                                        color: Colours.palette.m3primary
                                    }

                                    StyledRect {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Appearance.rounding.full
                                        color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background

                                        StyledRect {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.margins: parent.height * 0.25

                                            implicitWidth: height
                                            radius: Appearance.rounding.full
                                            color: Colours.palette.m3primary
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.topMargin: Appearance.spacing.normal
                                    text: qsTr("Dbus path")
                                }

                                StyledText {
                                    text: root.device?.dbusPath ?? ""
                                    color: Colours.palette.m3outline
                                    font.pointSize: Appearance.font.size.small
                                }

                                StyledText {
                                    Layout.topMargin: Appearance.spacing.normal
                                    text: qsTr("MAC address")
                                }

                                StyledText {
                                    text: root.device?.address ?? ""
                                    color: Colours.palette.m3outline
                                    font.pointSize: Appearance.font.size.small
                                }

                                StyledText {
                                    Layout.topMargin: Appearance.spacing.normal
                                    text: qsTr("Bonded")
                                }

                                StyledText {
                                    text: root.device?.bonded ? qsTr("Yes") : qsTr("No")
                                    color: Colours.palette.m3outline
                                    font.pointSize: Appearance.font.size.small
                                }

                                StyledText {
                                    Layout.topMargin: Appearance.spacing.normal
                                    text: qsTr("System name")
                                }

                                StyledText {
                                    text: root.device?.deviceName ?? ""
                                    color: Colours.palette.m3outline
                                    font.pointSize: Appearance.font.size.small
                                }
                            }
                        }
                    }
                }
            ]
        }
    }

    BluetoothFab {
        session: root.session
        device: root.device
        scrollX: root.contentX
        scrollY: root.contentY
        viewWidth: root.width
        viewHeight: root.height
    }
}
