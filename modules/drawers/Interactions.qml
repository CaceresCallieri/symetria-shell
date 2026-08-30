import qs.components.controls
import qs.config
import qs.services
import qs.modules.bar.popouts as BarPopouts
import Quickshell
import QtQuick

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property PersistentProperties visibilities
    required property Panels panels
    required property Item bar
    required property Item agentBar

    property point dragStart
    property bool utilitiesShortcutActive
    property real _pendingPopoutX

    function withinPanelHeight(panel: Item, y: real): bool {
        // `panel` lives inside `panels`, which is inset from this MouseArea by the
        // bar, while `y` arrives in THIS item's coordinates. Map the panel across
        // before comparing. Wrapper.qml's Region template already does exactly
        // this (`y: modelData.y + bar.implicitHeight`) when it carves the panel
        // out of the input mask; reading panel.y raw here put the hit test one
        // bar-height above the strip that actually receives the pointer.
        const panelY = panels.y + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    // Same mapping on the x axis, through the live container rather than through
    // Config.border.sideThickness. The two agree only because Panels' leftMargin
    // happens to BE that constant — which is exactly the coincidence that let the
    // y axis drift out of step with the input mask and go unnoticed for so long.
    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = panels.x + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    /// x-only edge test, for gestures where the pointer's height is irrelevant.
    /// Inclusive of the panel's left column: the input Region carved out of the
    /// mask spans [panel.x, panel.x + width], so a strict `>` rejected the first
    /// pixel of an already narrow strip after the pointer had been delivered to it.
    function pastRightEdgeOf(panel: Item, x: real): bool {
        return x >= panels.x + panel.x;
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return pastRightEdgeOf(panel, x) && withinPanelHeight(panel, y);
    }

    /// The right edge carries two OSD destinations stacked around the screen's
    /// vertical centre: volume above, brightness below. Whichever half the
    /// pointer is in picks the metric, so the card appears under the hand rather
    /// than wherever the last keypress left it.
    ///
    /// The two halves answer two different questions, and mixing them is a trap:
    /// membership uses the padded panel test (withinPanelHeight adds
    /// Config.border.rounding on each side, which is what makes the strip
    /// forgiving), but the metric is chosen by an UNPADDED comparison against the
    /// seam. Asking inRightPanel twice instead would hand the whole overlap — two
    /// roundings wide, straddling the centre — to whichever half ran first, and
    /// the split would sit off-centre by a band you cannot see.
    ///
    /// The cheap geometry test runs BEFORE resolving the overlay: this is called
    /// from onPositionChanged for every pointer sample across the whole window,
    /// and monitorFor plus a Map lookup on each one is real work for a question
    /// that is almost always "no".
    function showOsdForZone(x: real, y: real): void {
        if (!inRightPanel(panels.osdVolume, x, y) && !inRightPanel(panels.osdBrightness, x, y))
            return;

        const overlay = Visibilities.osdOverlays.get(Hypr.monitorFor(root.screen));
        if (!overlay)
            return;

        const seam = panels.y + panels.osdBrightness.y;
        overlay.showMetric(y < seam ? "volume" : "brightness");
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        return y < bar.implicitHeight + panel.y + panel.height && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real): bool {
        const panelBottomEdge = root.height - agentBar.implicitHeight;
        return y < panelBottomEdge
            && y > panelBottomEdge - panel.height - Config.border.rounding
            && withinPanelWidth(panel, x, y);
    }

    function inAgentBarForPanel(panel: Item, x: real, y: real): bool {
        return y >= root.height - agentBar.implicitHeight - Config.border.rounding && withinPanelWidth(panel, x, y);
    }

    // --- Keep-alive hysteresis helpers ---
    // When a drawer/popout is already open, these expanded zones prevent
    // accidental closure from small mouse deviations.

    function withinPanelWidthExpanded(panel: Item, x: real, y: real): bool {
        const margin = Config.border.rounding + Config.border.keepAliveMargin;
        const panelX = Config.border.sideThickness + panel.x;
        return x >= panelX - margin && x <= panelX + panel.width + margin;
    }

    function inTopPanelExpanded(panel: Item, x: real, y: real): bool {
        return y < bar.implicitHeight + panel.y + panel.height + Config.border.keepAliveMargin
            && withinPanelWidthExpanded(panel, x, y);
    }

    function inBottomPanelExpanded(panel: Item, x: real, y: real): bool {
        const panelBottomEdge = root.height - agentBar.implicitHeight;
        return y < panelBottomEdge
            && y > panelBottomEdge - panel.height - Config.border.rounding - Config.border.keepAliveMargin
            && withinPanelWidthExpanded(panel, x, y);
    }

    function inAgentBarForPanelExpanded(panel: Item, x: real, y: real): bool {
        return y >= root.height - agentBar.implicitHeight - Config.border.rounding && withinPanelWidthExpanded(panel, x, y);
    }

    // Narrower trigger zone for the utilities drawer — only the rightmost 1/4 of the panel width
    // activates on hover, so the user must move to the very bottom-right corner to trigger it.
    function inUtilitiesTriggerZone(panel: Item, x: real, y: real): bool {
        const triggerWidth = panel.width / 4;
        const panelRight = Config.border.sideThickness + panel.x + panel.width + Config.border.rounding;
        const triggerLeft = panelRight - triggerWidth;
        const inTriggerX = x >= triggerLeft && x <= panelRight;

        const panelBottomEdge = root.height - agentBar.implicitHeight;
        const inPanel = y < panelBottomEdge && y > panelBottomEdge - panel.height - Config.border.rounding;
        const inAgentBar = y >= root.height - agentBar.implicitHeight - Config.border.rounding;

        return inTriggerX && (inPanel || inAgentBar);
    }

    function onWheel(event: WheelEvent): void {
        if (event.y < bar.implicitHeight) {
            bar.handleWheel(event.x, event.angleDelta);
        }
    }

    anchors.fill: parent
    hoverEnabled: true

    onPressed: event => {
        dragStart = Qt.point(event.x, event.y);
        if (popouts.keyboardNavigationActive
                && !inTopPanelExpanded(panels.popouts, event.x, event.y)) {
            popouts.close();
        }
    }
    onContainsMouseChanged: {
        if (!containsMouse) {
            if (!utilitiesShortcutActive)
                visibilities.utilities = false;

            if (!popouts.keyboardNavigationActive
                    && (!popouts.currentName.startsWith("traymenu") || (popouts.current?.depth ?? 0) <= 1)
                    && !(popouts.currentName === "updates" && UpdateRunner.phase === "password")) {
                _popoutThrottleTimer.stop();
                popouts.hasCurrent = false;
                bar.closeTray();
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;
        }
    }

    onPositionChanged: event => {
        if (popouts.isDetached)
            return;

        // A keyboard-opened popout remains stable until Escape, the keybind, or
        // a click outside closes its focus grab. Pointer motion must not switch
        // its content or close it while the user navigates the list.
        if (popouts.keyboardNavigationActive)
            return;

        const x = event.x;
        const y = event.y;
        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        // Show bar in non-exclusive mode on hover
        if (!visibilities.bar && Config.bar.showOnHover && y < bar.implicitHeight)
            bar.isHovered = true;

        // Show/hide bar on drag (drag down to show, up to hide)
        if (pressed && dragStart.y < bar.implicitHeight) {
            if (dragY > Config.bar.dragThreshold)
                visibilities.bar = true;
            else if (dragY < -Config.bar.dragThreshold)
                visibilities.bar = false;
        }

        if (panels.sidebar.width === 0) {
            // Right-edge hover: upper zone summons volume, lower zone brightness
            showOsdForZone(x, y);

            const showSidebar = pressed && dragStart.x > 2 + panels.sidebar.x;

            if (showSidebar && dragX < -Config.sidebar.dragThreshold)
                visibilities.sidebar = true;
        } else {
            const outOfSidebar = x < width - panels.sidebar.width;

            // Right-edge hover, outside the sidebar
            if (outOfSidebar)
                showOsdForZone(x, y);

            // Hide sidebar on drag. Only the drag's starting x matters, which is
            // why this used to pass a literal y of 0 to neuter the height test —
            // now that withinPanelHeight maps coordinates properly, that trick
            // would reject every drag, so ask the x-only question directly.
            if (pressed && pastRightEdgeOf(panels.sidebar, dragStart.x) && dragX > Config.sidebar.dragThreshold)
                visibilities.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (Config.launcher.showOnHover) {
            if (!visibilities.launcher && (inBottomPanel(panels.launcher, x, y) || inAgentBarForPanel(panels.launcher, x, y)))
                visibilities.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                visibilities.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                visibilities.launcher = false;
        }

        // Show utilities on hover (corner-only trigger to open, full panel to keep alive)
        const showUtilities = inUtilitiesTriggerZone(panels.utilities, x, y);

        if (!utilitiesShortcutActive) {
            if (!visibilities.utilities) {
                // Open: require precise corner trigger
                if (showUtilities)
                    visibilities.utilities = true;
            } else {
                // Keep alive: use expanded full-panel zone so content is usable
                const inKeepAlive = inBottomPanelExpanded(panels.utilities, x, y)
                    || inAgentBarForPanelExpanded(panels.utilities, x, y);
                if (!inKeepAlive)
                    visibilities.utilities = false;
            }
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Show popouts on hover (throttled to ~60fps to avoid redundant childAt() work)
        if (y < bar.implicitHeight) {
            _pendingPopoutX = x;
            if (!_popoutThrottleTimer.running)
                _popoutThrottleTimer.start();
        } else if ((!popouts.currentName.startsWith("traymenu") || (popouts.current?.depth ?? 0) <= 1)
                   && !inTopPanelExpanded(panels.popouts, x, y)
                   && !(popouts.currentName === "updates" && UpdateRunner.phase === "password")) {
            _popoutThrottleTimer.stop();
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    // Throttle checkPopout to ~60fps (16ms) — without this, every mouse movement
    // event triggers childAt() traversals in Bar.qml, which is wasteful at 120+ Hz.
    Timer {
        id: _popoutThrottleTimer
        interval: 16
        onTriggered: {
            if (!root.popouts.keyboardNavigationActive)
                root.bar.checkPopout(root._pendingPopoutX);
        }
    }

    // Monitor individual visibility changes
    Connections {
        target: root.visibilities

        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags
            if (!root.visibilities.launcher) {
                root.utilitiesShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.visibilities.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inUtilitiesTriggerZone(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }
    }
}
