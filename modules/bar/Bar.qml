pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import qs.modules.recorder as RecorderModule
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
    // FORM axis: true when bar plates extend above the screen edge.
    readonly property bool bleeds: Theme.layout.barTopBleed > 0
    // External margin between glassmorphism pill components and adjacent bar entries
    readonly property int pillExternalMargin: Appearance.spacing.small

    // Split entries into left, center, right sections based on workspaces position
    // Single-pass processing for efficiency
    // intentional var: heterogeneous JS object { left: [], center: object|null, right: [] }
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

    // intentional var: JS array of heterogeneous config entry objects from _splitEntries
    readonly property var leftEntries: _splitEntries.left
    // intentional var: nullable JS config entry object from _splitEntries
    readonly property var centerEntry: _splitEntries.center
    // intentional var: JS array of heterogeneous config entry objects from _splitEntries
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

    function activatePopoutAtChild(popoutName: string, child: Item): void {
        popouts.currentName = popoutName;
        popouts.currentCenter = Qt.binding(() => child.mapToItem(root, child.implicitWidth / 2, 0).x);
        popouts.hasCurrent = true;
    }

    function openNamedPopout(popoutName: string): bool {
        const repeaters = [leftRepeater, rightRepeater];
        for (const repeater of repeaters) {
            for (let i = 0; i < repeater.count; i++) {
                const container = repeater.itemAt(i)?.item?.iconContainer;
                if (!container)
                    continue;

                for (const child of container.children) {
                    if (child?.name === popoutName && child.visible) {
                        activatePopoutAtChild(popoutName, child);
                        return true;
                    }
                }
            }
        }

        return false;
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
    function detectChildPopout(container: Item, x: real, nameResolver: var): bool {
        if (!container)
            return false;

        const childX = mapToItem(container, x, 0).x;
        const child = container.childAt(childX, container.height / 2);

        if (!child)
            return false;

        const popoutName = nameResolver(child);
        if (!popoutName)
            return false;

        activatePopoutAtChild(popoutName, child);
        return true;
    }

    /**
     * Determines if tray should show popout or expand (compact mode only).
     * In non-compact mode, always shows popout.
     * In compact mode, shows popout only if expanded AND cursor not over expand icon.
     */
    function shouldShowTrayPopout(trayItem: Item, x: real): bool {
        // Non-compact mode: always show popouts
        if (!Config.bar.tray.compact)
            return true;

        // Compact mode: only show if expanded
        if (!trayItem?.expanded)
            return false;

        // Don't show popout if cursor is over the expand icon
        const expandIcon = trayItem.expandIcon;
        if (!expandIcon)
            return true;

        const iconCoords = mapToItem(expandIcon, x, trayItem.implicitHeight / 2);
        return !expandIcon.contains(iconCoords);
    }

    /**
     * Finds the index of a child element in a Repeater.
     * Used to generate tray popout names like "traymenu0", "traymenu1", etc.
     */
    function findRepeaterIndex(repeater: Repeater, child: Item): int {
        if (!repeater)
            return -1;

        for (let i = 0; i < repeater.count; i++) {
            if (repeater.itemAt(i) === child)
                return i;
        }
        return -1;
    }

    /**
     * Finds which bar entry (BarLoader) contains the given x coordinate.
     * Searches both left and right sections.
     */
    function findBarEntryAt(x: real): var {
        const sections = [
            {
                section: leftSection,
                repeater: leftRepeater
            },
            {
                section: rightSection,
                repeater: rightRepeater
            }
        ];

        for (const {
            section,
            repeater
        } of sections) {
            if (x >= section.x && x <= section.x + section.width) {
                const relX = x - section.x;
                for (let i = 0; i < repeater.count; i++) {
                    const entry = repeater.itemAt(i);
                    if (entry?.enabled && relX >= entry.x && relX <= entry.x + entry.width) {
                        return {
                            entry,
                            section
                        };
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
            // Check recording center embed (not in left/right sections)
            if (recordingCenterContainer.visible) {
                const localPos = mapToItem(recordingCenterContainer, x, recordingCenterContainer.height / 2);
                if (localPos.x >= 0 && localPos.x <= recordingCenterContainer.width) {
                    popouts.currentName = "recording";
                    popouts.currentCenter = Qt.binding(() => recordingCenterContainer.mapToItem(root, recordingCenterContainer.width / 2, 0).x);
                    popouts.hasCurrent = true;
                    return;
                }
            }
            popouts.hasCurrent = false;
            return;
        }

        const {
            entry
        } = target;
        const id = entry.entryId;
        const item = entry.item;

        // StatusIcons: use iconContainer with named children
        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const container = item?.iconContainer;
            if (detectChildPopout(container, x, icon => icon?.name ?? null))
                return;
        }

        // Tray: use trayContainer with indexed children
        if (id === "tray" && Config.bar.popouts.tray) {
            if (shouldShowTrayPopout(item, x)) {
                const container = item?.trayContainer;
                const repeater = item?.trayItems;
                if (detectChildPopout(container, x, child => {
                    const idx = findRepeaterIndex(repeater, child);
                    return idx >= 0 ? `traymenu${idx}` : null;
                }))
                    return;
            } else {
                // Compact mode: expand tray instead of showing popout
                popouts.hasCurrent = false;
                if (item)
                    item.expanded = true;
                return;
            }
        }

        // TimePill: weather, clock, and date popouts
        if (id === "timePill" && Config.bar.popouts.timePill) {
            const container = item?.iconContainer;
            if (detectChildPopout(container, x, child => {
                const name = child?.name;
                if (name === "weather")
                    return "weather";
                if (name === "date" || name === "clock")
                    return "calendar";
                return null;
            }))
                return;
        }

        // SystemPill: updates and ram popouts
        if (id === "systemPill" && Config.bar.popouts.systemPill) {
            const container = item?.iconContainer;
            if (detectChildPopout(container, x, child => {
                const name = child?.name;
                if (name === "updates")
                    return "updates";
                if (name === "ram")
                    return "ram";
                return null;
            }))
                return;
        }

        popouts.hasCurrent = false;
    }

    /// Wheel handling for the whole bar strip. Interactions.qml forwards every
    /// wheel event whose y falls inside the bar, so these regions cover the empty
    /// space between widgets too, not just the widgets themselves.
    ///
    /// ALL THREE REGIONS ARE OFF in shell.json, which makes this a no-op today.
    /// That is deliberate, not neglect. Splitting the bar into half-screen zones
    /// gives the gesture no visual affordance: scrolling over a gap, the tray or
    /// the clock changed volume or brightness with nothing on screen to suggest
    /// it would, and both read as bugs rather than features. Re-enabling a region
    /// without first binding it to a specific widget brings that back.
    ///
    /// Each branch tests POSITION ONLY and checks its enable flag inside. An
    /// earlier version folded the flag into the position test
    /// (`x < screen.width / 2 && ...volume`), which made a DISABLED action fall
    /// through to the next branch — with volume off, scrolling the left half of
    /// the bar changed screen brightness. A region that is switched off must do
    /// nothing, never hand the gesture to its neighbour.
    function handleWheel(x: real, angleDelta: point): void {
        // Centre section — workspaces
        if (x >= centerLoader.x && x <= centerLoader.x + centerLoader.width) {
            if (!Config.bar.scrollActions.workspaces)
                return;

            const mon = (Config.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(`togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y < 0 || (Config.bar.workspaces.perMonitorWorkspaces ? mon.activeWorkspace?.id : Hypr.activeWsId) > 1)
                Hypr.dispatch(`workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
            return;
        }

        // Left half — volume. Off: the whole half reacted, including the gaps
        // left of the tray and any widget that does not handle its own wheel.
        if (x < screen.width / 2) {
            if (!Config.bar.scrollActions.volume)
                return;

            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
            return;
        }

        // Right half — brightness. Off: scrolling anywhere right of centre, over
        // the tray or the clock or the gaps between them, silently dimmed the
        // screen.
        if (!Config.bar.scrollActions.brightness)
            return;

        const monitor = Brightness.getMonitorForScreen(screen);
        if (angleDelta.y > 0)
            monitor?.setBrightness(monitor.brightness + Config.services.brightnessIncrement);
        else if (angleDelta.y < 0)
            monitor?.setBrightness(monitor.brightness - Config.services.brightnessIncrement);
    }

    // Left section - anchored to left
    RowLayout {
        id: leftSection
        anchors.left: parent.left
        anchors.leftMargin: leftRepeater.count > 0 ? root.hPadding : 0
        // FORM axis: when plates bleed past the screen edge they grow UPWARD, so
        // the row must hang from the bar's bottom instead of being centred in it
        // — otherwise the extra height splits evenly and half of it pushes the
        // content down instead of off-screen. Assigning `undefined` clears the
        // unused anchor; setting both at once is an error.
        anchors.bottom: root.bleeds ? parent.bottom : undefined
        anchors.verticalCenter: root.bleeds ? undefined : parent.verticalCenter
        spacing: Appearance.spacing.normal

        Repeater {
            id: leftRepeater
            model: root.leftEntries

            BarLoader {
                // intentional var: heterogeneous config entry JS object ({ id, enabled, ... })
                required property var modelData
                required property int index

                entryId: modelData.id
                entryEnabled: modelData.enabled !== false
                isFirst: index === 0
                isLast: false
            }
        }
    }

    // Center section - truly centered (workspaces)
    // Hidden when merged mode is active (workspaces move to the bottom merged bar).
    // _shouldBeActive drives the desired state; active stays true while opacity > 0
    // so the Loader keeps its content alive during the fade-out animation.
    Loader {
        id: centerLoader

        readonly property bool _shouldBeActive: root.centerEntry?.enabled !== false && !AgentService.mergeActive

        anchors.horizontalCenter: parent.horizontalCenter
        // The centre entry draws its own plate, so under the panel form it is
        // taller than the bar. Centring would split the excess evenly and push
        // half of it BELOW the bar; shifting up by half the bleed sends all of
        // it off the top instead, matching the bottom-anchored side rows.
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.bleeds ? -Theme.barPlateContentOffset : 0
        active: _shouldBeActive || opacity > 0
        opacity: _shouldBeActive ? 1 : 0
        visible: opacity > 0

        sourceComponent: Workspaces {
            screen: root.screen
        }

        Behavior on opacity {
            Anim {}
        }
    }

    // Recording bar embed — unified center embed for both STT and audio recording.
    // Scales from 0 → 1 with a slight overshoot when opening (and 1 → 0 when
    // closing), so the pill "pops" in/out at the bar center instead of being
    // revealed via a horizontal clip. The container's reserved layout width
    // follows the embed's visible scale (clamped at 1) so neighboring bar
    // sections reflow smoothly without being pushed by the overshoot peak.
    //
    // Animation is decoupled from service active states (which linger ~450ms
    // for the drawer hide animation) — instead, the job's `closing` signal
    // triggers the reverse scale animation immediately on cancel/restart.
    Item {
        id: recordingCenterContainer

        // Track the active job so _showEmbed can depend on its closing flag.
        // intentional var: polymorphic (SttJob | AudioRecorderJob | null)
        readonly property var _activeJob: RecordingSessionManager.currentJob

        // Declarative visibility — a pure function of current state.
        //
        // This replaced a procedurally-latched property that was updated by
        // three separate signal handlers (onActiveChanged / onClosingChanged
        // / on_ActiveJobChanged). That design had a latent failure mode: any
        // state transition that didn't fire all the relevant handlers could
        // leave _showEmbed stuck at the wrong value — which is exactly how
        // the STT restart regression happened (the lock-preservation fix
        // eliminated the activeChanged edge the old code relied on to
        // re-raise the embed). Deriving _showEmbed as a binding means it
        // re-evaluates whenever ANY source changes, so there's no "forgot to
        // flip it" failure mode. The close/open animations still play
        // correctly because the Behavior on the embed's scale animates
        // whenever the bound value changes.
        readonly property bool _showEmbed: RecordingSessionManager.active && !(_activeJob?.closing ?? false)

        readonly property bool _shouldBeActive: AgentService.mergeActive && _showEmbed

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        // visible must be true BEFORE width > 0 so children compute layout
        // sizes (Qt Quick Layouts defer when ancestors are invisible). The
        // embed.scale > epsilon term keeps us painted through the shrink
        // animation; once scale reaches 0 the container collapses to zero
        // width and we naturally hide.
        visible: _shouldBeActive || recordingEmbed.scale > 0.001

        // Reserve layout width proportional to the visible scale so the bar
        // collapses smoothly when scale-out completes. Clamped at 1.0 so the
        // overshoot peak (scale ≈ 1.05) doesn't push neighboring sections
        // outward — only the visual transform overflows, not the layout.
        implicitWidth: recordingEmbed.implicitWidth * Math.min(recordingEmbed.scale, 1.0)
        implicitHeight: recordingEmbed.implicitHeight
        width: implicitWidth
        height: implicitHeight

        RecorderModule.RecordingBarEmbed {
            id: recordingEmbed

            anchors.centerIn: parent
            transformOrigin: Item.Center
            scale: recordingCenterContainer._shouldBeActive ? 1.0 : 0.0

            // NOTE: duration is coupled to SttService.restartDelayTimer.interval.
            // The STT restart animation relies on the close (scale → 0) animation
            // finishing before _startInternal swaps _job to the new job (which
            // triggers the open scale → 1). If you change either duration, change
            // both — they must reference the same Appearance.anim.durations value.
            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.anim.durations.expressiveDefaultSpatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                }
            }
        }

        // Vocab hints popout trigger (STT mode only).
        Connections {
            target: SttService

            function onVocabHintsVisibleChanged(): void {
                if (!recordingCenterContainer._shouldBeActive)
                    return;

                if (SttService.vocabHintsVisible) {
                    root.popouts.currentName = "recording";
                    root.popouts.currentCenter = Qt.binding(() => recordingCenterContainer.mapToItem(root, recordingCenterContainer.width / 2, 0).x);
                    root.popouts.hasCurrent = true;
                } else if (root.popouts.currentName === "recording") {
                    root.popouts.hasCurrent = false;
                }
            }
        }
    }

    // Right section - anchored to right
    RowLayout {
        id: rightSection
        anchors.right: parent.right
        anchors.rightMargin: rightRepeater.count > 0 ? root.hPadding : 0
        // See leftSection for why this hangs from the bottom when bleeding.
        anchors.bottom: root.bleeds ? parent.bottom : undefined
        anchors.verticalCenter: root.bleeds ? undefined : parent.verticalCenter
        spacing: Appearance.spacing.normal

        Repeater {
            id: rightRepeater
            model: root.rightEntries

            BarLoader {
                // intentional var: heterogeneous config entry JS object ({ id, enabled, ... })
                required property var modelData
                required property int index

                entryId: modelData.id
                entryEnabled: modelData.enabled !== false
                isFirst: false
                isLast: index === rightRepeater.count - 1
            }
        }
    }

    // Shared loader component for left and right sections
    component BarLoader: Loader {
        id: barLoader

        required property string entryId
        required property bool entryEnabled
        property bool isFirst: false
        property bool isLast: false

        // Glassmorphism pill entries that need external margins for visual separation
        // Add new pill component IDs here when extending the bar
        readonly property bool hasPillMargins: entryId === "tray" || entryId === "statusIcons" || entryId === "timePill" || entryId === "systemPill"

        // Only entries that draw a PLATE carry the extra bleed height, so only
        // they may bottom-align. Anything else (logo, power, workspaces spacer)
        // is a short item and would be pinned to the bar's bottom edge instead
        // of centred; it stays vertically centred, shifted onto the VISIBLE
        // band by the same offset the plates use for their content.
        Layout.alignment: (root.bleeds && hasPillMargins) ? Qt.AlignBottom : Qt.AlignVCenter
        Layout.topMargin: (root.bleeds && !hasPillMargins) ? Theme.layout.barTopBleed : 0
        Layout.leftMargin: hasPillMargins ? root.pillExternalMargin : 0
        Layout.rightMargin: hasPillMargins ? root.pillExternalMargin : 0
        visible: entryEnabled
        active: entryEnabled

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
