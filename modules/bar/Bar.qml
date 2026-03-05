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
    readonly property int hPadding: Config.bar.sizes.edgePadding
    // External margin between glassmorphism pill components and adjacent bar entries
    readonly property int pillExternalMargin: Appearance.spacing.small

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
            if (entry.id === "spacer")
                continue;
            if (i === centerIndex)
                continue;

            if (centerIndex === -1 || i < centerIndex)
                left.push(entry);
            else
                right.push(entry);
        }

        return {
            left,
            center,
            right
        };
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

    // ─────────────────────────────────────────────────────────────────────────
    // Popout Detection System
    //
    // Components that support popouts must expose:
    //   - PillContainer-based (StatusIcons, TimePill, SystemPill):
    //     property alias iconContainer (RowLayout with named children)
    //     Each child must have: property string name
    //   - Tray (special case due to expand/collapse behavior):
    //     property alias trayContainer (Row), property alias trayItems (Repeater)
    //     property alias expandIcon (Loader), property bool expanded
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Unified hit-testing for popout detection using childAt().
     * Maps cursor position to container's coordinate space and finds the child element.
     *
     * @param container - The layout container (Row/RowLayout) to search in
     * @param x - Cursor x position in Bar's coordinate space
     * @param nameResolver - Function(child) => string|null that returns popout name for a child
     * @returns true if popout was activated, false otherwise
     */
    function detectChildPopout(container: Item, x: real, nameResolver): bool {
        if (!container) return false;

        const childX = mapToItem(container, x, 0).x;
        const child = container.childAt(childX, container.height / 2);

        if (!child) return false;

        const popoutName = nameResolver(child);
        if (!popoutName) return false;

        popouts.currentName = popoutName;
        popouts.currentCenter = Qt.binding(() => child.mapToItem(root, child.implicitWidth / 2, 0).x);
        popouts.hasCurrent = true;
        return true;
    }

    /**
     * Determines if tray should show popout or expand (compact mode only).
     * In non-compact mode, always shows popout.
     * In compact mode, shows popout only if expanded AND cursor not over expand icon.
     */
    function shouldShowTrayPopout(trayItem: Item, x: real): bool {
        // Non-compact mode: always show popouts
        if (!Config.bar.tray.compact) return true;

        // Compact mode: only show if expanded
        if (!trayItem?.expanded) return false;

        // Don't show popout if cursor is over the expand icon
        const expandIcon = trayItem.expandIcon;
        if (!expandIcon) return true;

        const iconCoords = mapToItem(expandIcon, x, trayItem.implicitHeight / 2);
        return !expandIcon.contains(iconCoords);
    }

    /**
     * Finds the index of a child element in a Repeater.
     * Used to generate tray popout names like "traymenu0", "traymenu1", etc.
     */
    function findRepeaterIndex(repeater, child: Item): int {
        if (!repeater) return -1;

        for (let i = 0; i < repeater.count; i++) {
            if (repeater.itemAt(i) === child) return i;
        }
        return -1;
    }

    /**
     * Finds which bar entry (BarLoader) contains the given x coordinate.
     * Searches both left and right sections.
     */
    function findBarEntryAt(x: real): var {
        const sections = [
            { section: leftSection, repeater: leftRepeater },
            { section: rightSection, repeater: rightRepeater }
        ];

        for (const { section, repeater } of sections) {
            if (x >= section.x && x <= section.x + section.width) {
                const relX = x - section.x;
                for (let i = 0; i < repeater.count; i++) {
                    const entry = repeater.itemAt(i);
                    if (entry?.enabled && relX >= entry.x && relX <= entry.x + entry.width) {
                        return { entry, section };
                    }
                }
            }
        }
        return null;
    }

    function checkPopout(x: real): void {
        const target = findBarEntryAt(x);

        if (target?.entry?.entryId !== "tray")
            closeTray();

        if (!target) {
            popouts.hasCurrent = false;
            return;
        }

        const { entry } = target;
        const id = entry.entryId;
        const item = entry.item;

        // StatusIcons: use iconContainer with named children
        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const container = item?.iconContainer;
            if (detectChildPopout(container, x, (icon) => icon?.name ?? null))
                return;
        }

        // Tray: use trayContainer with indexed children
        if (id === "tray" && Config.bar.popouts.tray) {
            if (shouldShowTrayPopout(item, x)) {
                const container = item?.trayContainer;
                const repeater = item?.trayItems;
                if (detectChildPopout(container, x, (child) => {
                    const idx = findRepeaterIndex(repeater, child);
                    return idx >= 0 ? `traymenu${idx}` : null;
                }))
                    return;
            } else {
                // Compact mode: expand tray instead of showing popout
                popouts.hasCurrent = false;
                if (item) item.expanded = true;
                return;
            }
        }

        // TimePill: weather, clock, and date popouts
        if (id === "timePill" && Config.bar.popouts.timePill) {
            const container = item?.iconContainer;
            if (detectChildPopout(container, x, (child) => {
                const name = child?.name;
                if (name === "weather") return "weather";
                if (name === "date" || name === "clock") return "calendar";
                return null;
            }))
                return;
        }

        // SystemPill: updates and ram popouts
        if (id === "systemPill" && Config.bar.popouts.systemPill) {
            const container = item?.iconContainer;
            if (detectChildPopout(container, x, (child) => {
                const name = child?.name;
                if (name === "updates") return "updates";
                if (name === "ram") return "ram";
                return null;
            }))
                return;
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

        // Glassmorphism pill entries that need external margins for visual separation
        // Add new pill component IDs here when extending the bar
        readonly property bool hasPillMargins: entryId === "tray"
            || entryId === "statusIcons"
            || entryId === "timePill"
            || entryId === "systemPill"

        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: hasPillMargins ? root.pillExternalMargin : 0
        Layout.rightMargin: hasPillMargins ? root.pillExternalMargin : 0
        visible: enabled
        active: enabled

        sourceComponent: {
            switch (entryId) {
            case "logo":
                return logoComp;
            case "tray":
                return trayComp;
            case "timePill":
                return timePillComp;
            case "systemPill":
                return systemPillComp;
            case "statusIcons":
                return statusIconsComp;
            case "power":
                return powerComp;
            default:
                return null;
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
        id: timePillComp
        TimePill {}
    }

    Component {
        id: systemPillComp
        SystemPill {}
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
