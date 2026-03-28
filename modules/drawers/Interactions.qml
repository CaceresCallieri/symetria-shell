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

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = Config.border.thickness + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = Config.border.thickness + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < Config.border.thickness + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Config.border.thickness + panel.x && withinPanelHeight(panel, x, y);
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

    // Narrower trigger zone for the utilities drawer — only the rightmost 1/4 of the panel width
    // activates on hover, so the user must move to the very bottom-right corner to trigger it.
    function inUtilitiesTriggerZone(panel: Item, x: real, y: real): bool {
        const triggerWidth = panel.width / 4;
        const panelRight = Config.border.thickness + panel.x + panel.width + Config.border.rounding;
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

    onPressed: event => dragStart = Qt.point(event.x, event.y)
    onContainsMouseChanged: {
        if (!containsMouse) {
            if (!utilitiesShortcutActive)
                visibilities.utilities = false;

            if (!popouts.currentName.startsWith("traymenu") || (popouts.current?.depth ?? 0) <= 1) {
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
            // Show OSD overlay on right-edge hover
            if (inRightPanel(panels.osd, x, y))
                Visibilities.osdOverlays.get(Hypr.monitorFor(root.screen))?.show();

            const showSidebar = pressed && dragStart.x > Config.border.thickness + panels.sidebar.x;

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.session, dragStart.x, dragStart.y) && withinPanelHeight(panels.session, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.width >= panels.session.nonAnimWidth && dragX < -Config.sidebar.dragThreshold)
                    visibilities.sidebar = true;
            } else if (showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                visibilities.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width;

            // Show OSD overlay on right-edge hover (outside sidebar)
            if (outOfSidebar && inRightPanel(panels.osd, x, y))
                Visibilities.osdOverlays.get(Hypr.monitorFor(root.screen))?.show();

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.session, dragStart.x, dragStart.y) && withinPanelHeight(panels.session, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
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

        // DISABLED: Dashboard panel (bottom-left hover zone)
        // The dashboard module is disabled and slated for removal.
        // Some sub-features (weather/forecast) may be extracted and reimplemented elsewhere.
        // To re-enable: set Config.dashboard.enabled to true in shell.json and uncomment below.
        //
        // const showDashboard = Config.dashboard.showOnHover && (inBottomLeftPanel(panels.dashboard, x, y) || inAgentBarForPanel(panels.dashboard, x, y));
        //
        // if (!dashboardShortcutActive) {
        //     visibilities.dashboard = showDashboard;
        // } else if (showDashboard) {
        //     dashboardShortcutActive = false;
        // }
        //
        // if (pressed && inBottomLeftPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
        //     if (dragY < -Config.dashboard.dragThreshold)
        //         visibilities.dashboard = true;
        //     else if (dragY > Config.dashboard.dragThreshold)
        //         visibilities.dashboard = false;
        // }

        // Show utilities on hover (corner-only trigger zone)
        const showUtilities = inUtilitiesTriggerZone(panels.utilities, x, y);

        // Always update visibility based on hover if not in shortcut mode
        if (!utilitiesShortcutActive) {
            visibilities.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Show popouts on hover
        if (y < bar.implicitHeight) {
            bar.checkPopout(x);
        } else if ((!popouts.currentName.startsWith("traymenu") || (popouts.current?.depth ?? 0) <= 1) && !inTopPanel(panels.popouts, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
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
