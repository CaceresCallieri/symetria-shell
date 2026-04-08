import QtQuick

QtObject {
    required property var service // intentional var: duck-typed — any QtObject with refCount property

    Component.onCompleted: service.refCount++
    Component.onDestruction: service.refCount--
}
