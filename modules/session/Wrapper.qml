pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

Item {
    id: root

    required property PersistentProperties visibilities
    required property var panels
    readonly property real nonAnimWidth: content.implicitWidth

    visible: opacity > 0
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    opacity: 0
    scale: 0.9
    transformOrigin: Item.Center

    states: State {
        name: "visible"
        when: root.visibilities.session && Config.session.enabled

        PropertyChanges {
            root.opacity: 1
            root.scale: 1
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                }
                Anim {
                    target: root
                    property: "scale"
                    easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                }
            }
        },
        Transition {
            from: "visible"
            to: ""

            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                }
                Anim {
                    target: root
                    property: "scale"
                    easing.bezierCurve: Appearance.anim.curves.emphasized
                }
            }
        }
    ]

    Loader {
        id: content

        Component.onCompleted: active = Qt.binding(() => (root.visibilities.session && Config.session.enabled) || root.visible)

        sourceComponent: Content {
            visibilities: root.visibilities
        }
    }
}
