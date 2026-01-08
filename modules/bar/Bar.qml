pragma ComponentBehavior: Bound

import qs.services
import qs.config
import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property BarPopouts.Wrapper popouts
    readonly property int hPadding: Appearance.padding.large

    // Split entries into left, center, right sections based on workspaces position
    // Single-pass processing for efficiency
    readonly property var _splitEntries: {
        const entries = Config.bar.entries;
        const left = [];
        const right = [];
        let center = null;
        let centerIndex = -1;

        // Find workspaces index
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].id === "workspaces") {
                centerIndex = i;
                center = entries[i];
                break;
            }
        }

        // Split entries: items before workspaces go left, after go right
        // Spacers are ignored (no longer needed in three-section layout)
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (entry.id === "spacer") continue;
            if (i === centerIndex) continue;

            if (centerIndex === -1 || i < centerIndex) left.push(entry);
            else right.push(entry);
        }

        return { left, center, right };
    }

    readonly property var leftEntries: _splitEntries.left
    readonly property var centerEntry: _splitEntries.center
    readonly property var rightEntries: _splitEntries.right

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < rightRepeater.count; i++) {
            const item = rightRepeater.itemAt(i);
            if (item?.enabled && item.entryId === "tray") {
                item.item.expanded = false;
            }
        }
    }

    function checkPopout(x: real): void {
        let targetChild = null;
        let targetSection = null;

        // Check left section first
        if (x >= leftSection.x && x <= leftSection.x + leftSection.width) {
            const relX = x - leftSection.x;
            for (let i = 0; i < leftRepeater.count; i++) {
                const item = leftRepeater.itemAt(i);
                if (item?.enabled && relX >= item.x && relX <= item.x + item.width) {
                    targetChild = item;
                    targetSection = leftSection;
                    break;
                }
            }
        }

        // Check right section if not found in left
        if (!targetChild && x >= rightSection.x) {
            const relX = x - rightSection.x;
            for (let i = 0; i < rightRepeater.count; i++) {
                const item = rightRepeater.itemAt(i);
                if (item?.enabled && relX >= item.x && relX <= item.x + item.width) {
                    targetChild = item;
                    targetSection = rightSection;
                    break;
                }
            }
        }

        if (targetChild?.entryId !== "tray")
            closeTray();

        if (targetChild) {
            const id = targetChild.entryId;
            const left = targetChild.x + targetSection.x;
            const item = targetChild.item;
            const itemWidth = item?.implicitWidth ?? 0;

            if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
                const items = item.items;
                const icon = items.childAt(mapToItem(items, x, 0).x, items.height / 2);
                if (icon) {
                    popouts.currentName = icon.name;
                    popouts.currentCenter = Qt.binding(() => icon.mapToItem(root, icon.implicitWidth / 2, 0).x);
                    popouts.hasCurrent = true;
                    return;
                }
            } else if (id === "tray" && Config.bar.popouts.tray) {
                if (!Config.bar.tray.compact || (item.expanded && !item.expandIcon.contains(mapToItem(item.expandIcon, x, item.implicitHeight / 2)))) {
                    const index = Math.floor(((x - left - item.padding * 2 + item.spacing) / item.layout.implicitWidth) * item.items.count);
                    const trayItem = item.items.itemAt(index);
                    if (trayItem) {
                        popouts.currentName = `traymenu${index}`;
                        popouts.currentCenter = Qt.binding(() => trayItem.mapToItem(root, trayItem.implicitWidth / 2, 0).x);
                        popouts.hasCurrent = true;
                        return;
                    }
                } else {
                    popouts.hasCurrent = false;
                    item.expanded = true;
                    return;
                }
            }
        }

        popouts.hasCurrent = false;
    }

    function handleWheel(x: real, angleDelta: point): void {
        // Check if over workspaces (center section)
        if (x >= centerLoader.x && x <= centerLoader.x + centerLoader.width) {
            if (Config.bar.scrollActions.workspaces) {
                const mon = (Config.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
                const specialWs = mon?.lastIpcObject.specialWorkspace.name;
                if (specialWs?.length > 0)
                    Hypr.dispatch(`togglespecialworkspace ${specialWs.slice(8)}`);
                else if (angleDelta.y < 0 || (Config.bar.workspaces.perMonitorWorkspaces ? mon.activeWorkspace?.id : Hypr.activeWsId) > 1)
                    Hypr.dispatch(`workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
            }
        } else if (x < screen.width / 2 && Config.bar.scrollActions.volume) {
            // Volume scroll on left half
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            // Brightness scroll on right half
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + Config.services.brightnessIncrement);
            else if (angleDelta.y < 0)
                monitor.setBrightness(monitor.brightness - Config.services.brightnessIncrement);
        }
    }

    // Left section - anchored to left
    RowLayout {
        id: leftSection
        anchors.left: parent.left
        anchors.leftMargin: leftRepeater.count > 0 ? root.hPadding : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.normal

        Repeater {
            id: leftRepeater
            model: root.leftEntries

            BarLoader {
                required property var modelData
                required property int index

                entryId: modelData.id
                enabled: modelData.enabled !== false
                isFirst: index === 0
                isLast: false
            }
        }
    }

    // Center section - truly centered (workspaces)
    Loader {
        id: centerLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        active: root.centerEntry?.enabled !== false
        visible: active

        sourceComponent: Workspaces {
            screen: root.screen
        }
    }

    // Right section - anchored to right
    RowLayout {
        id: rightSection
        anchors.right: parent.right
        anchors.rightMargin: rightRepeater.count > 0 ? root.hPadding : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.normal

        Repeater {
            id: rightRepeater
            model: root.rightEntries

            BarLoader {
                required property var modelData
                required property int index

                entryId: modelData.id
                enabled: modelData.enabled !== false
                isFirst: false
                isLast: index === rightRepeater.count - 1
            }
        }
    }

    // Shared loader component for left and right sections
    component BarLoader: Loader {
        id: barLoader

        required property string entryId
        required property bool enabled
        property bool isFirst: false
        property bool isLast: false

        Layout.alignment: Qt.AlignVCenter
        visible: enabled
        active: enabled

        sourceComponent: {
            switch (entryId) {
                case "logo": return logoComp;
                case "tray": return trayComp;
                case "clock": return clockComp;
                case "statusIcons": return statusIconsComp;
                case "power": return powerComp;
                default: return null;
            }
        }
    }

    // Component definitions
    Component {
        id: logoComp
        OsIcon {}
    }

    Component {
        id: trayComp
        Tray {}
    }

    Component {
        id: clockComp
        Clock {}
    }

    Component {
        id: statusIconsComp
        StatusIcons {}
    }

    Component {
        id: powerComp
        Power {
            visibilities: root.visibilities
        }
    }
}
