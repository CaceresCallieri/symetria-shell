import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

PillCard {
    id: root

    required property var visibilities
    required property Item popouts

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Appearance.padding.large * 2

    // Default fill / radius come from PillCard's claymorphism recipe.

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Appearance.padding.large
        spacing: Appearance.spacing.normal

        StyledText {
            text: qsTr("Quick Toggles")
            font.pointSize: Appearance.font.size.normal
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Appearance.spacing.small

            Toggle {
                icon: "wifi"
                checked: Network.wifiEnabled
                onClicked: Network.toggleWifi()
            }

            Toggle {
                icon: "bluetooth"
                checked: Bluetooth.defaultAdapter?.enabled ?? false
                onClicked: {
                    const adapter = Bluetooth.defaultAdapter;
                    if (adapter)
                        adapter.enabled = !adapter.enabled;
                }
            }

            Toggle {
                icon: "mic"
                checked: !Audio.sourceMuted
                onClicked: {
                    const audio = Audio.source?.audio;
                    if (audio)
                        audio.muted = !audio.muted;
                }
            }

            Toggle {
                icon: "gamepad"
                checked: GameMode.enabled
                onClicked: GameMode.enabled = !GameMode.enabled
            }

            Toggle {
                icon: "notifications_off"
                checked: Notifs.dnd
                onClicked: Notifs.dnd = !Notifs.dnd
            }

            Toggle {
                icon: "vpn_key"
                checked: VPN.connected
                enabled: !VPN.connecting
                visible: VPN.enabled
                onClicked: VPN.toggle()
            }

            // Settings entry — placed last and forced into the same raised
            // claymorphism aesthetic as the inactive toggles, so it doesn't
            // visually stand alone. `toggle: false` keeps its semantics as a
            // pure action (no on/off state); `raised: true` overrides
            // IconButton's auto-derivation (which would flatten it because
            // toggle is false) to keep the look consistent across the row.
            Toggle {
                icon: "settings"
                inactiveOnColour: Colours.palette.m3onSurfaceVariant
                toggle: false
                raised: true
                onClicked: {
                    root.visibilities.utilities = false;
                    root.popouts.detach("network");
                }
            }

        }
    }

    component Toggle: IconButton {
        Layout.fillWidth: true
        Layout.preferredWidth: implicitWidth + (stateLayer.pressed ? Appearance.padding.large : internalChecked ? Appearance.padding.smaller : 0)
        // Constant pill rounding across active / inactive — the visual
        // differentiation now comes from PillToggleSurface's inset depth +
        // brighter fill, so we no longer need the Material "circle → rounded
        // square morph" radius shift to signal state.
        radius: Appearance.rounding.normal
        inactiveColour: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background
        toggle: true

        Behavior on Layout.preferredWidth {
            Anim {
                duration: Appearance.anim.durations.expressiveFastSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
            }
        }
    }
}
