pragma Singleton

import QtQuick

QtObject {
    property QtObject socket
    readonly property string runtimeDirectory: "/offscreen-runtime"
}
