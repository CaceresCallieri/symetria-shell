pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Pam pam
    property string buffer

    Layout.fillWidth: true
    Layout.fillHeight: true

    clip: true

    Connections {
        target: root.pam

        function onBufferChanged(): void {
            if (root.pam.buffer.length > root.buffer.length) {
                charList.bindImWidth();
            } else if (root.pam.buffer.length === 0) {
                // Freeze the width by assigning the current value over the
                // binding, so the dots animate out instead of the list snapping
                // shut underneath them. Looks like a no-op; it is not.
                charList.implicitWidth = charList.implicitWidth;
            }

            root.buffer = root.pam.buffer;
        }
    }

    // NO placeholder text. An empty field shows nothing at all — the flat,
    // unlabelled pill is the intended look.
    //
    // Nothing was lost by removing it: its three states are all covered
    // elsewhere now. "Loading..." is the submit button turning into a spinner,
    // the max-tries text is one of the PAM messages under the field, and
    // "Enter your password" labelled the only input on an otherwise empty
    // screen.

    ListView {
        id: charList

        readonly property int fullWidth: count * (implicitHeight + spacing) - spacing

        function bindImWidth(): void {
            imWidthBehavior.enabled = false;
            implicitWidth = Qt.binding(() => fullWidth);
            imWidthBehavior.enabled = true;
        }

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: implicitWidth > root.width ? -(implicitWidth - root.width) / 2 : 0

        implicitWidth: fullWidth
        implicitHeight: Appearance.font.size.normal

        orientation: Qt.Horizontal
        spacing: Appearance.spacing.small / 2
        interactive: false

        model: ScriptModel {
            values: root.buffer.split("")
        }

        delegate: StyledRect {
            id: ch

            implicitWidth: implicitHeight
            implicitHeight: charList.implicitHeight

            color: Colours.palette.m3onSurface
            radius: Appearance.rounding.small / 2

            opacity: 0
            scale: 0
            Component.onCompleted: {
                opacity = 1;
                scale = 1;
            }
            ListView.onRemove: removeAnim.start()

            SequentialAnimation {
                id: removeAnim

                PropertyAction {
                    target: ch
                    property: "ListView.delayRemove"
                    value: true
                }
                ParallelAnimation {
                    Anim {
                        target: ch
                        property: "opacity"
                        to: 0
                    }
                    Anim {
                        target: ch
                        property: "scale"
                        to: 0.5
                    }
                }
                PropertyAction {
                    target: ch
                    property: "ListView.delayRemove"
                    value: false
                }
            }

            Behavior on opacity {
                Anim {}
            }

            Behavior on scale {
                Anim {
                    duration: Appearance.anim.durations.expressiveFastSpatial
                    easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
                }
            }
        }

        Behavior on implicitWidth {
            id: imWidthBehavior

            Anim {}
        }
    }
}
