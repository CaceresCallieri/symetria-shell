import QtQuick

QtObject {
    id: root

    // intentional var: nullable polymorphic — DesktopEntry or JS app object from launcher model
    property var active: null
}
