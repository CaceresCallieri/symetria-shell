import QtQuick

QtObject {
    id: root

    // intentional var: nullable polymorphic — NmcliWifi network object (JS object from nmcli scan data)
    property var active: null
    property bool showPasswordDialog: false
    // intentional var: nullable JS object from network scan data ({ ssid, bssid, security, ... })
    property var pendingNetwork: null
}
