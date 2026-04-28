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

    readonly property bool isOpen: root.visibilities.session && Config.session.enabled

    visible: opacity > 0
    // Width/height MUST collapse to 0 when closed. The drawer window uses an
    // XOR input mask (modules/drawers/Wrapper.qml:94-123) that subtracts each
    // panel's bounds from the screen — and inverted-XOR semantics make those
    // subtracted bounds the only region that captures input. A non-zero idle
    // size here would permanently trap clicks in the screen center, blocking
    // pass-through to the desktop. See docs/qml-pitfalls.md (XOR mask inversion).
    implicitWidth: isOpen ? content.implicitWidth : 0
    implicitHeight: isOpen ? content.implicitHeight : 0

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

        // Centered on the wrapper so the menu stays visually centered even
        // while the wrapper itself is 0x0 during the closing animation.
        anchors.centerIn: parent

        active: root.isOpen || root.visible

        sourceComponent: Content {
            visibilities: root.visibilities
        }
    }
}
