pragma ComponentBehavior: Bound

import qs.components
import qs.components.effects
import qs.services
import qs.config
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    spacing: 0

    readonly property var dividerPill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    property Component leftContent: null
    property Component rightContent: null
    
    property real leftWidthRatio: 0.4
    property int leftMinimumWidth: 420
    property var leftLoaderProperties: ({})
    property var rightLoaderProperties: ({})
    
    property alias leftLoader: leftLoader
    property alias rightLoader: rightLoader

    Item {
        id: leftPane

        Layout.preferredWidth: Math.floor(parent.width * root.leftWidthRatio)
        Layout.minimumWidth: root.leftMinimumWidth
        Layout.fillHeight: true

        ClippingRectangle {
            id: leftClippingRect

            anchors.fill: parent
            anchors.margins: Appearance.padding.normal
            anchors.leftMargin: 0
            anchors.rightMargin: Appearance.padding.normal / 2

            radius: leftBorder.innerRadius
            color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, 0.1).background

            Loader {
                id: leftLoader

                anchors.fill: parent
                anchors.margins: Appearance.padding.large + Appearance.padding.normal
                anchors.leftMargin: Appearance.padding.large
                anchors.rightMargin: Appearance.padding.large + Appearance.padding.normal / 2

                asynchronous: true
                sourceComponent: root.leftContent

                Component.onCompleted: {
                    for (const key in root.leftLoaderProperties) {
                        leftLoader[key] = root.leftLoaderProperties[key];
                    }
                }
            }
        }

        InnerBorder {
            id: leftBorder

            borderColor: root.dividerPill.border
            leftThickness: 0
            rightThickness: Appearance.padding.normal / 2
        }
    }

    Item {
        id: rightPane

        Layout.fillWidth: true
        Layout.fillHeight: true

        ClippingRectangle {
            id: rightClippingRect

            anchors.fill: parent
            anchors.margins: Appearance.padding.normal
            anchors.leftMargin: 0
            anchors.rightMargin: Appearance.padding.normal / 2

            radius: rightBorder.innerRadius
            color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, 0.1).background

            Loader {
                id: rightLoader

                anchors.fill: parent
                anchors.margins: Appearance.padding.large * 2

                asynchronous: true
                sourceComponent: root.rightContent

                Component.onCompleted: {
                    for (const key in root.rightLoaderProperties) {
                        rightLoader[key] = root.rightLoaderProperties[key];
                    }
                }
            }
        }

        InnerBorder {
            id: rightBorder

            borderColor: root.dividerPill.border
            leftThickness: Appearance.padding.normal / 2
        }
    }
}

