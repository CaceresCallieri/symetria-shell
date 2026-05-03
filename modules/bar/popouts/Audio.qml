pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../controlcenter/network"

PillCardSection {
    id: root

    required property Item wrapper

    implicitWidth: layout.implicitWidth + root.contentMargins * 2

    ButtonGroup {
        id: sinks
    }

    ButtonGroup {
        id: sources
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.normal

        StyledText {
            text: qsTr("Output device")
            font.weight: 500
        }

        Repeater {
            model: Audio.sinks

            StyledRadioButton {
                id: control

                required property PwNode modelData

                ButtonGroup.group: sinks
                checked: Audio.sink?.id === modelData.id
                onClicked: Audio.setAudioSink(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Appearance.spacing.smaller
            text: qsTr("Input device")
            font.weight: 500
        }

        Repeater {
            model: Audio.sources

            StyledRadioButton {
                required property PwNode modelData

                ButtonGroup.group: sources
                checked: Audio.source?.id === modelData.id
                onClicked: Audio.setAudioSource(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Appearance.spacing.smaller
            Layout.bottomMargin: -Appearance.spacing.small / 2
            text: qsTr("Volume (%1)").arg(Audio.muted ? qsTr("Muted") : `${Math.round(Audio.volume * 100)}%`)
            font.weight: 500
        }

        CustomMouseArea {
            Layout.fillWidth: true
            implicitHeight: Appearance.padding.normal * 3

            onWheel: event => {
                if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
                else if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
            }

            StyledSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: parent.implicitHeight

                value: Audio.volume
                onMoved: Audio.setVolume(value)

                Behavior on value {
                    Anim {}
                }
            }
        }

        // Always-raised neumorphic action pill — drops the previous flat
        // IconTextButton in favor of the shell-wide Tier 2 toggle surface,
        // so the "Open settings" affordance now reads as a pressable
        // action against the surrounding claymorphism card. `active: false`
        // is fixed since this is an action, not a toggleable state.
        PillToggleSurface {
            id: settingsBtn

            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.normal
            implicitHeight: settingsRow.implicitHeight + Appearance.padding.normal * 2
            active: false

            StateLayer {
                color: Colours.palette.m3onSurface

                function onClicked(): void {
                    root.wrapper.detach("audio");
                }
            }

            RowLayout {
                id: settingsRow

                anchors.centerIn: parent
                spacing: Appearance.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: "settings"
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Open settings")
                    color: Colours.palette.m3onSurface
                }
            }
        }
    }
}
