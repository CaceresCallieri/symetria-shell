pragma ComponentBehavior: Bound

import ".."
import "../components"
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property Session session

    spacing: Appearance.spacing.normal

    SettingsHeader {
        icon: "wifi"
        title: qsTr("Network settings")
    }

    SectionHeader {
        Layout.topMargin: Appearance.spacing.large
        title: qsTr("WiFi status")
        description: qsTr("General WiFi settings")
    }

    SectionContainer {
        ToggleRow {
            label: qsTr("WiFi enabled")
            checked: NmcliWifi.wifiEnabled
            toggle.onToggled: {
                NmcliWifi.enableWifi(checked);
            }
        }
    }

    SectionHeader {
        Layout.topMargin: Appearance.spacing.large
        title: qsTr("Network information")
        description: qsTr("Current network connection")
    }

    SectionContainer {
        contentSpacing: Appearance.spacing.small / 2

        PropertyRow {
            label: qsTr("Connected network")
            value: NmcliWifi.active ? NmcliWifi.active.ssid : qsTr("Not connected")
        }

        PropertyRow {
            showTopMargin: true
            label: qsTr("Signal strength")
            value: NmcliWifi.active ? qsTr("%1%").arg(NmcliWifi.active.strength) : qsTr("N/A")
        }

        PropertyRow {
            showTopMargin: true
            label: qsTr("Security")
            value: NmcliWifi.active ? (NmcliWifi.active.isSecure ? qsTr("Secured") : qsTr("Open")) : qsTr("N/A")
        }

        PropertyRow {
            showTopMargin: true
            label: qsTr("Frequency")
            value: NmcliWifi.active ? qsTr("%1 MHz").arg(NmcliWifi.active.frequency) : qsTr("N/A")
        }
    }
}