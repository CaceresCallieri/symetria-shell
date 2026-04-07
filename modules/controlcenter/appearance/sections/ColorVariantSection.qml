pragma ComponentBehavior: Bound

import ".."
import "../../../launcher/services"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

CollapsibleSection {
    title: qsTr("Color variant")
    description: qsTr("Material theme variant")
    showBackground: true

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.small / 2

        Repeater {
            model: M3Variants.list

            delegate: StyledRect {
                // intentional var: heterogeneous JS object from M3Variants.list ({ variant, ... })
                required property var modelData

                Layout.fillWidth: true

                // intentional var: heterogeneous JS object { background: color, border: color } from pillStyle()
                readonly property var activePill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.strong)

                color: modelData.variant === Schemes.currentVariant ? activePill.background : "transparent"
                radius: Appearance.rounding.normal
                border.width: modelData.variant === Schemes.currentVariant ? 1 : 0
                border.color: modelData.variant === Schemes.currentVariant ? activePill.border : "transparent"

                StateLayer {
                    function onClicked(): void {
                        const variant = modelData.variant;

                        Schemes.currentVariant = variant;
                        Quickshell.execDetached(["symmetria", "scheme", "set", "-v", variant]);

                        Qt.callLater(() => {
                            reloadTimer.restart();
                        });
                    }
                }

                Timer {
                    id: reloadTimer
                    interval: 300
                    onTriggered: {
                        Schemes.reload();
                    }
                }

                RowLayout {
                    id: variantRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Appearance.padding.normal

                    spacing: Appearance.spacing.normal

                    MaterialIcon {
                        text: modelData.icon
                        font.pointSize: Appearance.font.size.large
                        fill: modelData.variant === Schemes.currentVariant ? 1 : 0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.name
                        font.weight: modelData.variant === Schemes.currentVariant ? 500 : 400
                    }

                    MaterialIcon {
                        visible: modelData.variant === Schemes.currentVariant
                        text: "check"
                        color: Colours.palette.m3primary
                        font.pointSize: Appearance.font.size.large
                    }
                }

                implicitHeight: variantRow.implicitHeight + Appearance.padding.normal * 2
            }
        }
    }
}

