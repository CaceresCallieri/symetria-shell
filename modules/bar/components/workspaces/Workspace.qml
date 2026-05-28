import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property int wsId
    required property int activeWsId
    // intentional var: JS object used as hash map ({ [wsId]: bool })
    required property var occupied

    readonly property bool isWorkspace: true // Flag for finding workspace children
    readonly property bool isActive: activeWsId === ws
    // Padding = space inside the selector pill (both sides)
    readonly property int activePadding: Appearance.padding.large
    // Margin = configurable gap outside the selector pill (both sides)
    // Set to 0 for no gap, or use Appearance.padding.* values for visible separation
    readonly property int activeMargin: 0
    // Content size: actual visual width of workspace content (indicator text + window icons)
    readonly property int contentSize: implicitWidth + (hasWindows ? Appearance.padding.small : 0)
    // Indicator offset: how far left the indicator extends from workspace.x
    // Used by ActiveIndicator to position itself correctly
    readonly property int indicatorOffset: isActive ? activePadding : 0
    // Indicator size: total width the indicator pill should be
    // Used by ActiveIndicator to set its width
    readonly property int indicatorSize: contentSize + (isActive ? activePadding * 2 : 0)

    readonly property int ws: wsId
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows && isActive

    // Cached workspace reference to avoid repeated find() lookups.
    // Hypr.workspaceById() centralizes the .find() pattern shared with the
    // merged agentbar pill and AgentService.
    // intentional var: Hyprland workspace proxy from .find() — nullable, identity-unstable
    readonly property var currentWorkspace: Hypr.workspaceById(root.ws)

    // Icon resolution: named workspace icon → first letter → roman numeral
    readonly property string rawIcon: {
        if (root.currentWorkspace) {
            const customIcon = Icons.getNamedWsIcon(root.currentWorkspace.name);
            if (customIcon && customIcon !== Icons.materialIconPrefix) return customIcon;
            if (root.ws < 0 && root.currentWorkspace.name) return root.currentWorkspace.name[0].toUpperCase();
        }
        return Icons.romanize(root.ws);
    }

    // Color varies by active/occupied state for visual hierarchy
    readonly property color indicatorColor: {
        if (root.isActive)
            return Colours.palette.m3onSurface;
        if (Config.bar.workspaces.occupiedBg || root.isOccupied)
            return Colours.palette.m3onSurface;
        return Colours.layer(Colours.palette.m3outlineVariant, 2);
    }

    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: contentSize
    Layout.leftMargin: isActive ? activePadding + activeMargin : 0
    Layout.rightMargin: isActive ? activePadding + activeMargin : 0

    implicitWidth: innerLayout.implicitWidth
    implicitHeight: innerLayout.implicitHeight

    // Workspace-level click: switch workspace or toggle special.
    // Declared before innerLayout so it has lower z-order — app icon
    // MouseAreas inside innerLayout sit on top and receive clicks first.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: event => {
            if (!root.isActive) {
                // Named workspaces (negative IDs) need "workspace name:<name>" syntax
                if (root.ws < 0) {
                    const wsObj = Hypr.workspaceById(root.ws);
                    if (wsObj) Hypr.dispatch(`workspace name:${wsObj.name}`);
                } else {
                    Hypr.dispatch(`workspace ${root.ws}`);
                }
            } else if (event.x < content.labelWidth) {
                // Only toggle special workspace when clicking on the label area,
                // not on app icons gaps or the fullscreen indicator
                Hypr.dispatch("togglespecialworkspace special");
            }
        }
    }

    RowLayout {
        id: innerLayout

        anchors.fill: parent
        spacing: 0

        WorkspaceContent {
            id: content

            wsId: root.ws
            icon: root.rawIcon
            hasWindows: root.hasWindows
            labelColor: root.indicatorColor
            animateLabel: true
            windowsLeftMargin: -Config.bar.sizes.innerWidth / 10  // Pull icons closer for tighter grouping
            animateWindowsWidth: false  // Root RowLayout animates width; inner animation would double-ease
        }

        // Fullscreen/Maximize indicator - shared with the merged agentbar pill.
        WorkspaceFullscreenIndicator {
            wsId: root.ws
            isActive: root.isActive
        }
    }

    Behavior on Layout.preferredWidth {
        Anim {}
    }

    Behavior on Layout.leftMargin {
        Anim {}
    }

    Behavior on Layout.rightMargin {
        Anim {}
    }
}
