pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property SelectionModel selectionModel
    property string imageSource: ""
    property color accentColor: "white"
    readonly property real aspect: selectionModel.output ? selectionModel.output.width / selectionModel.output.height : 16 / 9
    readonly property alias stageWidth: stage.width
    readonly property alias stageHeight: stage.height

    Item {
        id: stage
        anchors.centerIn: parent
        width: Math.min(root.width, root.height * root.aspect)
        height: width / root.aspect

        Rectangle {
            anchors.fill: parent
            color: "#151515"
        }
        Image {
            anchors.fill: parent
            source: root.imageSource
            sourceSize: Qt.size(1600, 1600)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        // Four scrims leave the selected pixels undimmed without a shader.
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property var crop: root.selectionModel.region // intentional var: normalized rectangle
                readonly property real cropLeft: (crop?.x ?? 0) * stage.width
                readonly property real cropTop: (crop?.y ?? 0) * stage.height
                readonly property real cropRight: cropLeft + (crop?.width ?? 0) * stage.width
                readonly property real cropBottom: cropTop + (crop?.height ?? 0) * stage.height
                x: index === 1 || index === 3 ? cropLeft : index === 2 ? cropRight : 0
                y: index === 3 ? cropBottom : index === 0 || index === 2 ? 0 : 0
                width: index === 1 || index === 3 ? cropRight - cropLeft : index === 0 ? cropLeft : stage.width - cropRight
                height: index === 1 ? cropTop : index === 3 ? stage.height - cropBottom : stage.height
                color: "#99000000"
                visible: crop !== null
            }
        }

        Rectangle {
            id: selection
            readonly property var crop: root.selectionModel.region // intentional var: normalized rectangle
            visible: crop !== null
            x: (crop?.x ?? 0) * stage.width
            y: (crop?.y ?? 0) * stage.height
            width: (crop?.width ?? 0) * stage.width
            height: (crop?.height ?? 0) * stage.height
            color: "transparent"
            border.color: root.accentColor
            border.width: 2
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            property real startX: 0
            property real startY: 0
            onPressed: mouse => {
                startX = mouse.x / width;
                startY = mouse.y / height;
                root.selectionModel.dragRegion(startX, startY, startX, startY);
            }
            onPositionChanged: mouse => {
                if (pressed)
                    root.selectionModel.dragRegion(startX, startY, mouse.x / width, mouse.y / height);
            }
            onReleased: mouse => root.selectionModel.dragRegion(startX, startY, mouse.x / width, mouse.y / height)
        }

        Repeater {
            model: 4
            Rectangle {
                id: handle
                required property int index
                readonly property bool cropRight: index % 2 === 1
                readonly property bool cropBottom: index > 1
                visible: selection.visible
                x: selection.x + (cropRight ? selection.width : 0) - width / 2
                y: selection.y + (cropBottom ? selection.height : 0) - height / 2
                width: 10
                height: 10
                radius: 5
                color: root.accentColor
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5
                    cursorShape: handle.cropRight === handle.cropBottom ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                    property real anchorX: 0
                    property real anchorY: 0
                    onPressed: {
                        const crop = root.selectionModel.region;
                        anchorX = crop.x + (handle.cropRight ? 0 : crop.width);
                        anchorY = crop.y + (handle.cropBottom ? 0 : crop.height);
                    }
                    onPositionChanged: mouse => {
                        if (pressed) {
                            const point = mapToItem(stage, mouse.x, mouse.y);
                            root.selectionModel.dragRegion(anchorX, anchorY, point.x / stage.width, point.y / stage.height);
                        }
                    }
                }
            }
        }
    }
}
