pragma ComponentBehavior: Bound

import ".."
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.containers
import qs.services
import qs.config
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Session session

    // intentional var: heterogeneous JS { background, border } from pillStyle()
    readonly property var contentPill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, 0.1)
    readonly property var borderPill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    // Local mirrors of Config, written back together in saveConfig().
    property bool weatherUseCurrentLocation: Config.services.weatherUseCurrentLocation ?? false
    property string weatherLocation: Config.services.weatherLocation ?? ""
    property bool useFahrenheit: Config.services.useFahrenheit ?? false
    property bool useTwelveHourClock: Config.services.useTwelveHourClock ?? false

    anchors.fill: parent

    function saveConfig(): void {
        Config.services.weatherUseCurrentLocation = root.weatherUseCurrentLocation;
        Config.services.weatherLocation = root.weatherLocation;
        Config.services.useFahrenheit = root.useFahrenheit;
        Config.services.useTwelveHourClock = root.useTwelveHourClock;
        Config.save();
    }

    ClippingRectangle {
        id: clip

        anchors.fill: parent
        anchors.margins: Appearance.padding.normal
        anchors.leftMargin: 0
        anchors.rightMargin: Appearance.padding.normal

        radius: paneBorder.innerRadius
        color: root.contentPill.background

        Loader {
            anchors.fill: parent
            anchors.margins: Appearance.padding.large + Appearance.padding.normal
            anchors.leftMargin: Appearance.padding.large
            anchors.rightMargin: Appearance.padding.large

            asynchronous: true
            sourceComponent: contentComponent
        }
    }

    InnerBorder {
        id: paneBorder

        borderColor: root.borderPill.border
        leftThickness: 0
        rightThickness: Appearance.padding.normal
    }

    Component {
        id: contentComponent

        StyledFlickable {
            id: flick

            flickableDirection: Flickable.VerticalFlick
            contentHeight: layout.height

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: flick
            }

            ColumnLayout {
                id: layout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                spacing: Appearance.spacing.normal

                StyledText {
                    text: qsTr("Weather")
                    font.pointSize: Appearance.font.size.large
                    font.weight: 500
                }

                SectionContainer {
                    Layout.fillWidth: true
                    alignTop: true

                    StyledText {
                        text: qsTr("Location")
                        font.pointSize: Appearance.font.size.normal
                    }

                    SwitchRow {
                        label: qsTr("Use current location (GPS)")
                        checked: root.weatherUseCurrentLocation
                        onToggled: checked => {
                            root.weatherUseCurrentLocation = checked;
                            root.saveConfig();
                        }
                    }

                    // Shown only once the async geoclue probe has finished and found it
                    // missing, while GPS mode is enabled — falls back to IP meanwhile.
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.weatherUseCurrentLocation && Weather.geoclueChecked && !Weather.geoclueAvailable
                        wrapMode: Text.WordWrap
                        color: Colours.palette.m3error
                        font.pointSize: Appearance.font.size.small
                        text: qsTr("geoclue service file not found — GPS may be unavailable, using IP location instead. Install: sudo -A pacman -S geoclue, then ensure 'symmetria' is whitelisted in /etc/geoclue/geoclue.conf")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Manual location (city or lat,long)")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.small
                        opacity: root.weatherUseCurrentLocation ? 0.5 : 1
                    }

                    StyledInputField {
                        Layout.fillWidth: true
                        horizontalAlignment: TextInput.AlignLeft
                        enabled: !root.weatherUseCurrentLocation
                        text: root.weatherLocation
                        onEditingFinished: {
                            root.weatherLocation = text;
                            root.saveConfig();
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.small
                        text: Weather.city ? qsTr("Showing weather for %1").arg(Weather.city) : qsTr("Locating…")
                    }
                }

                SectionContainer {
                    Layout.fillWidth: true
                    alignTop: true

                    StyledText {
                        text: qsTr("Units")
                        font.pointSize: Appearance.font.size.normal
                    }

                    SwitchRow {
                        label: qsTr("Use Fahrenheit")
                        checked: root.useFahrenheit
                        onToggled: checked => {
                            root.useFahrenheit = checked;
                            root.saveConfig();
                        }
                    }

                    SwitchRow {
                        label: qsTr("12-hour clock")
                        checked: root.useTwelveHourClock
                        onToggled: checked => {
                            root.useTwelveHourClock = checked;
                            root.saveConfig();
                        }
                    }
                }
            }
        }
    }
}
