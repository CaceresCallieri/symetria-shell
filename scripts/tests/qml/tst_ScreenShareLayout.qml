pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import "../../../modules/screenshare" as ScreenShare

TestCase {
    id: test

    name: "NativeScreenShareLayout"
    when: windowShown
    // TestCase defaults to hidden. Visible controls exercise real layout and
    // rendering behavior; qmltestrunner still uses the offscreen platform.
    visible: true
    width: 1920
    height: 1200

    ScreenShare.HeaderLayout {
        id: header

        property real fontScale: 1
        width: 900
        height: implicitHeight
        leading: Rectangle {
            implicitWidth: 20
            implicitHeight: 20
        }
        heading: ColumnLayout {
            Text {
                Layout.fillWidth: true
                text: "Compartir pantalla"
                font.pointSize: 16 * header.fontScale
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: "Elegí qué querés mostrar."
                font.pointSize: 12 * header.fontScale
                elide: Text.ElideRight
            }
        }
        trailing: Button {
            implicitWidth: 32
            implicitHeight: 32
        }
    }

    Button {
        id: button

        y: 120
        width: 450
        height: 40
        padding: 12
        contentItem: ScreenShare.CenteredRow {
            Rectangle {
                id: icon

                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 16
                implicitHeight: 16
            }
            Text {
                id: label

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: "Ventanas"
                font.family: "monospace"
                font.pointSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    function test_header_alignment_data() {
        const rows = [];
        for (const width of [320, 600, 1200, 1800])
            for (const scale of [1, 1.5])
                rows.push({
                    tag: `${width}-${scale}`,
                    width,
                    scale
                });
        return rows;
    }

    function test_header_alignment(data) {
        header.width = data.width;
        header.fontScale = data.scale;
        verify(waitForRendering(header));
        const close = header.trailingItem;
        const position = close.mapToItem(header, 0, 0);
        fuzzyCompare(position.x + close.width, header.width, 0.75);
        fuzzyCompare(position.y + close.height / 2, header.height / 2, 0.75);
        verify(header.height >= close.height);
    }

    function test_button_alignment_data() {
        const rows = [];
        for (const width of [72, 160, 450, 800])
            for (const hasIcon of [true, false])
                rows.push({
                    tag: `${width}-${hasIcon}`,
                    width,
                    hasIcon
                });
        return rows;
    }

    function test_button_alignment(data) {
        button.width = data.width;
        icon.visible = data.hasIcon;
        // Descendant layouts polish after icon visibility changes. Wait for
        // a rendered frame, not only the Button's own polish operation.
        verify(waitForRendering(button));
        const first = data.hasIcon ? icon : label;
        const left = first.mapToItem(button, 0, 0).x;
        const right = label.mapToItem(button, label.width, 0).x;
        fuzzyCompare((left + right) / 2, button.width / 2, 0.75);
        verify(left >= button.leftPadding - 0.75);
        verify(right <= button.width - button.rightPadding + 0.75);
        if (data.hasIcon) {
            fuzzyCompare(icon.mapToItem(button, 0, icon.height / 2).y, label.mapToItem(button, 0, label.height / 2).y, 0.75);
        }
    }
}
