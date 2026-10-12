pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Status icons pill - shows system status indicators (audio, network, bluetooth, battery, etc.).
// Uses PillContainer base for consistent styling with other bar pills.

PillContainer {
    id: root

    // `colour` is inherited from PillContainer on purpose — see the rationale
    // on that property. Do not redeclare it here; that shadows rather than
    // overrides.

    // Popout interface: container with named WrappedLoader children (each has 'name' property)
    iconContainer: iconColumn

    RowLayout {
        id: iconColumn

        anchors.centerIn: parent

        spacing: Appearance.spacing.smaller / 2

        // Left padding spacer
        Item {
            implicitWidth: root.pillPadding
            implicitHeight: 1
        }

        // Lock keys status - collapse left margin when both indicators are hidden
        // to prevent extra gap at the start of the pill
        PillContainer.WrappedLoader {
            name: "lockstatus"
            active: Config.bar.status.showLockStatus

            // Collapse spacing when loader is active but no lock icons are visible
            Layout.leftMargin: (Config.bar.status.showLockStatus && !Hypr.capsLock && !Hypr.numLock) ? -iconColumn.spacing : 0

            sourceComponent: RowLayout {
                spacing: 0

                Item {
                    implicitHeight: capslockIcon.implicitHeight
                    implicitWidth: Hypr.capsLock ? capslockIcon.implicitWidth : 0

                    BarIcon {
                        id: capslockIcon

                        anchors.centerIn: parent

                        scale: Hypr.capsLock ? 1 : 0.5
                        opacity: Hypr.capsLock ? 1 : 0

                        icon: "keyboard_capslock_badge"
                        tint: root.colour
                        tintAlpha: BarGlyphs.statusAlpha

                        Behavior on opacity {
                            Anim {}
                        }

                        Behavior on scale {
                            Anim {}
                        }
                    }

                    Behavior on implicitWidth {
                        Anim {}
                    }
                }

                Item {
                    Layout.leftMargin: Hypr.capsLock && Hypr.numLock ? iconColumn.spacing : 0

                    implicitHeight: numlockIcon.implicitHeight
                    implicitWidth: Hypr.numLock ? numlockIcon.implicitWidth : 0

                    BarIcon {
                        id: numlockIcon

                        anchors.centerIn: parent

                        scale: Hypr.numLock ? 1 : 0.5
                        opacity: Hypr.numLock ? 1 : 0

                        icon: "looks_one"
                        tint: root.colour
                        tintAlpha: BarGlyphs.statusAlpha

                        Behavior on opacity {
                            Anim {}
                        }

                        Behavior on scale {
                            Anim {}
                        }
                    }

                    Behavior on implicitWidth {
                        Anim {}
                    }
                }
            }
        }

        // Audio icon
        PillContainer.WrappedLoader {
            name: "audio"
            active: Config.bar.status.showAudio

            sourceComponent: BarIcon {
                animate: true
                icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                tint: root.colour
                tintAlpha: BarGlyphs.statusAlpha
            }
        }

        // Microphone icon
        PillContainer.WrappedLoader {
            name: "audio"
            active: Config.bar.status.showMicrophone

            sourceComponent: BarIcon {
                animate: true
                icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                tint: root.colour
                tintAlpha: BarGlyphs.statusAlpha
            }
        }

        // Keyboard layout icon
        PillContainer.WrappedLoader {
            name: "kblayout"
            active: Config.bar.status.showKbLayout

            sourceComponent: StyledText {
                animate: true
                text: Hypr.kbLayout
                color: root.colour
                font.family: Appearance.font.family.mono
            }
        }

        // Network icon
        PillContainer.WrappedLoader {
            name: "network"
            active: Config.bar.status.showNetwork

            sourceComponent: BarIcon {
                animate: true
                icon: NmcliWifi.active ? Icons.getNetworkIcon(NmcliWifi.active.strength ?? 0) : "wifi_off"
                tint: root.colour
                tintAlpha: BarGlyphs.statusAlpha
            }
        }

        // Ethernet icon
        PillContainer.WrappedLoader {
            name: "ethernet"
            active: Config.bar.status.showNetwork && NmcliEthernet.activeEthernet

            sourceComponent: BarIcon {
                animate: true
                icon: "cable"
                tint: root.colour
                tintAlpha: BarGlyphs.statusAlpha
            }
        }

        // Bluetooth section
        PillContainer.WrappedLoader {
            Layout.preferredWidth: implicitWidth

            name: "bluetooth"
            active: Config.bar.status.showBluetooth

            sourceComponent: RowLayout {
                spacing: Appearance.spacing.smaller / 2

                // Bluetooth icon
                BarIcon {
                    animate: true
                    icon: {
                        if (!Bluetooth.defaultAdapter?.enabled)
                            return "bluetooth_disabled";
                        if (Bluetooth.devices.values.some(d => d.connected))
                            return "bluetooth_connected";
                        return "bluetooth";
                    }
                    tint: root.colour
                    tintAlpha: BarGlyphs.statusAlpha
                }

                // Connected bluetooth devices
                Repeater {
                    model: ScriptModel {
                        values: Bluetooth.devices.values.filter(d => d.state !== BluetoothDeviceState.Disconnected)
                    }

                    BarIcon {
                        id: device

                        required property BluetoothDevice modelData

                        animate: true
                        icon: Icons.getBluetoothIcon(modelData?.icon)
                        tint: root.colour
                        tintAlpha: BarGlyphs.statusAlpha
                        fill: 1

                        SequentialAnimation on opacity {
                            running: device.modelData?.state !== BluetoothDeviceState.Connected
                            alwaysRunToEnd: true
                            loops: Animation.Infinite

                            Anim {
                                from: 1
                                to: 0
                                duration: Appearance.anim.durations.large
                                easing.bezierCurve: Appearance.anim.curves.standardAccel
                            }
                            Anim {
                                from: 0
                                to: 1
                                duration: Appearance.anim.durations.large
                                easing.bezierCurve: Appearance.anim.curves.standardDecel
                            }
                        }
                    }
                }
            }

            Behavior on Layout.preferredWidth {
                Anim {}
            }
        }

        // Power profile icon — dedicated slot. Icon mirrors PowerMode.activeMode
        // (Silent + the three PPD profiles). Clicking cycles through every mode
        // in PowerMode.modes order, Silent included. Hover triggers the
        // "powerprofile" popout via Bar.qml:checkPopout; the inner MouseArea
        // handles click-to-cycle without consuming hover events (hoverEnabled
        // stays false) so the screen-wide Interactions area still drives popout
        // detection.
        PillContainer.WrappedLoader {
            name: "powerprofile"
            active: Config.bar.status.showPowerProfile

            sourceComponent: MouseArea {
                implicitWidth: profileIcon.implicitWidth
                implicitHeight: profileIcon.implicitHeight

                hoverEnabled: false

                onClicked: PowerMode.cycle()

                BarIcon {
                    id: profileIcon

                    anchors.centerIn: parent
                    animate: true
                    // Glyph follows the active mode (PowerMode owns the ordered
                    // set, so a future mode brings its own icon for free).
                    icon: PowerMode.activeMode.icon
                    tint: PowerProfiles.degradationReason !== PerformanceDegradationReason.None ? Colours.palette.m3powerButton : root.colour
                    tintAlpha: BarGlyphs.statusAlpha
                    fill: 1
                }
            }
        }

        // Battery icon
        PillContainer.WrappedLoader {
            name: "battery"
            // Hide on non-laptop hardware when the dedicated power-profile icon is shown — both
            // icons would otherwise display the same profile glyph simultaneously.
            active: Config.bar.status.showBattery && (UPower.displayDevice.isLaptopBattery || !Config.bar.status.showPowerProfile)

            sourceComponent: BarIcon {
                animate: true
                icon: {
                    if (!UPower.displayDevice.isLaptopBattery)
                        return PowerMode.activeMode.icon;

                    const perc = UPower.displayDevice.percentage;
                    const charging = [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state);
                    if (perc === 1)
                        return charging ? "battery_charging_full" : "battery_full";
                    let level = Math.floor(perc * 7);
                    if (charging && (level === 4 || level === 1))
                        level--;
                    return charging ? `battery_charging_${(level + 3) * 10}` : `battery_${level}_bar`;
                }
                tint: !UPower.onBattery || UPower.displayDevice.percentage > 0.2 ? root.colour : Colours.palette.m3error
                tintAlpha: BarGlyphs.statusAlpha
                fill: 1
            }
        }

        // Dictation streaming active indicator — appears while STT streaming
        // mode is toggled on (Super+Alt+D → SttService.streamingActive).
        PillContainer.WrappedLoader {
            name: "dictation"
            active: Config.bar.status.showDictationStatus && SttService.streamingActive

            sourceComponent: BarIcon {
                animate: true
                icon: "graphic_eq"
                tint: root.colour
                tintAlpha: BarGlyphs.statusAlpha
            }
        }

        // Right padding spacer
        Item {
            implicitWidth: root.pillPadding
            implicitHeight: 1
        }
    }
}
