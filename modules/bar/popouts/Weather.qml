pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

Column {
    id: root

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.weatherWidth

    // Header: Icon + Temp + Location
    RowLayout {
        width: parent.width
        spacing: Appearance.spacing.normal

        MaterialIcon {
            text: Weather.icon
            color: Colours.palette.m3primary
            font.pointSize: Appearance.font.size.extraLarge
        }

        Column {
            Layout.fillWidth: true
            spacing: Appearance.spacing.smaller

            StyledText {
                text: Weather.temp
                font.pointSize: Appearance.font.size.large
                font.weight: 500
            }

            StyledText {
                text: Weather.city ? `${Weather.description} in ${Weather.city}` : Weather.description
                font.pointSize: Appearance.font.size.small
                opacity: 0.8
            }
        }
    }

    // Separator
    Rectangle {
        width: parent.width
        height: 1
        color: Colours.palette.m3outline
        opacity: 0.3
    }

    // Weather details
    Column {
        width: parent.width
        spacing: Appearance.spacing.small

        DetailRow {
            icon: "device_thermostat"
            label: qsTr("Feels like")
            value: Weather.feelsLike
        }

        DetailRow {
            icon: "humidity_percentage"
            label: qsTr("Humidity")
            value: `${Weather.humidity}%`
        }

        DetailRow {
            icon: "air"
            label: qsTr("Wind")
            value: `${Weather.windSpeed} km/h`
        }
    }

    // Separator
    Rectangle {
        width: parent.width
        height: 1
        color: Colours.palette.m3outline
        opacity: 0.3
    }

    // Sunrise/Sunset row
    RowLayout {
        width: parent.width

        // Sunrise (left-aligned)
        Row {
            spacing: Appearance.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "wb_sunny"
                color: Colours.palette.m3tertiary
                font.pointSize: Appearance.font.size.normal
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.sunrise
                font.family: Appearance.font.family.mono
            }
        }

        // Spacer to push sunset to the right
        Item {
            Layout.fillWidth: true
        }

        // Sunset (right-aligned)
        Row {
            spacing: Appearance.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "nights_stay"
                color: Colours.palette.m3tertiary
                font.pointSize: Appearance.font.size.normal
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.sunset
                font.family: Appearance.font.family.mono
            }
        }
    }

    // Reusable detail row component
    component DetailRow: RowLayout {
        required property string icon
        required property string label
        required property string value

        width: parent.width
        spacing: Appearance.spacing.small

        MaterialIcon {
            text: parent.icon
            color: Colours.palette.m3secondary
            font.pointSize: Appearance.font.size.normal
        }

        StyledText {
            Layout.fillWidth: true
            text: parent.label
            opacity: 0.8
        }

        StyledText {
            text: parent.value
            font.family: Appearance.font.family.mono
            font.weight: 500
        }
    }
}
