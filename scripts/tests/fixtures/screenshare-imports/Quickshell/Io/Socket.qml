import QtQuick
import ScreenShareTest 1.0

// Record the transport boundary while the test runs the production singleton.
QtObject {
    property bool connected: false
    property string path: ""
    property QtObject parser
    property var messages: [] // intentional var: recorded outbound JSON objects
    signal connectionStateChanged

    function write(value: string): void {
        messages = messages.concat([JSON.parse(value)]);
    }

    function flush(): void {
    }

    onConnectedChanged: connectionStateChanged()
    Component.onCompleted: Bridge.socket = this
}
