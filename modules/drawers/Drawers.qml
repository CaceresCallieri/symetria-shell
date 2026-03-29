pragma ComponentBehavior: Bound

// Lightweight wrapper — NO heavy module imports here.
// DrawersImpl.qml in content/ has the actual content and loads asynchronously
// to defer ~61 files of cascading QML compilation from blocking startup.
import Quickshell
import QtQuick

Variants {
    model: Quickshell.screens

    LazyLoader {
        required property ShellScreen modelData
        loading: true
        source: Qt.resolvedUrl("content/DrawersImpl.qml")
    }
}
