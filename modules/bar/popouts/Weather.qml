pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Bar weather popout — two claymorphism PillCard sections replace the
// prior dividers-between-sections layout. The header card carries the
// hero info (condition icon, temperature, city, today's range); the
// secondary card groups all the supporting numerics (feels-like,
// humidity, wind, sunrise/sunset) into a single coherent block.
// Dashboard's weather pane is unaffected (this file only powers the bar
// popout).
Column {
    id: root

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.weatherWidth

    // Section 1 — Header card: condition icon + temperature + city +
    // today's min/max range. The most prominent section, sized by the
    // large temp glyph.
    Item {
        width: parent.width
        implicitHeight: headerRow.implicitHeight + Appearance.padding.normal * 2

        PillCard {
            anchors.fill: parent
        }

        RowLayout {
            id: headerRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Appearance.padding.normal
            anchors.rightMargin: Appearance.padding.normal
            spacing: Appearance.spacing.normal

            MaterialIcon {
                text: Weather.icon
                color: Colours.palette.m3primary
                font.pointSize: Appearance.font.size.extraLarge
            }

            Column {
                Layout.fillWidth: true
                spacing: 0

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

            // Today's min/max range (right-aligned, subdued).
            Column {
                visible: Weather.forecast.length > 0
                Layout.alignment: Qt.AlignVCenter
                spacing: Appearance.spacing.smaller

                TempBound { icon: "arrow_drop_up"; value: Weather.tempMax }
                TempBound { icon: "arrow_drop_down"; value: Weather.tempMin }
            }
        }
    }

    // Section 2 — Secondary metrics card: groups feels-like / humidity /
    // wind with the sunrise/sunset row inside a single frame. Keeping
    // them in one card preserves the "supporting numerics" reading
    // without re-introducing the divider hierarchy that the cards
    // already replace.
    Item {
        width: parent.width
        implicitHeight: detailsColumn.implicitHeight + Appearance.padding.normal * 2

        PillCard {
            anchors.fill: parent
        }

        Column {
            id: detailsColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Appearance.padding.normal
            anchors.rightMargin: Appearance.padding.normal
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

            // Sunrise / sunset — sibling row inside the same card, no
            // divider; the icon-glyph contrast (wb_sunny / nights_stay)
            // already separates it visually from the metric rows above.
            RowLayout {
                width: parent.width

                // Sunrise (left-aligned).
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

                // Spacer to push sunset to the right.
                Item {
                    Layout.fillWidth: true
                }

                // Sunset (right-aligned).
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

    component TempBound: Row {
        required property string icon
        required property string value

        // Tight spacing — icon glyphs have internal whitespace
        spacing: 2

        MaterialIcon {
            text: parent.icon
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3onSurface
            opacity: 0.5
        }

        StyledText {
            text: parent.value
            font.pointSize: Appearance.font.size.small
            font.family: Appearance.font.family.mono
            opacity: 0.5
        }
    }
}
