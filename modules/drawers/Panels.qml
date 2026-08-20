import qs.components
import qs.config
import qs.services
import qs.modules.launcher as Launcher
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities as Utilities
import qs.modules.sidebar as Sidebar
import qs.modules.clipboard as ClipboardModule
import qs.modules.askpass as Askpass
import qs.modules.recorder as RecorderModule
import qs.modules.calculator as CalculatorModule
import qs.modules.packages as PackagesModule
import qs.modules.videotrim as VideoTrimModule
import Quickshell
import QtQuick

Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property Item bar
    required property Item agentBar

    readonly property alias osdVolume: osdVolume
    readonly property alias osdBrightness: osdBrightness

    /// The screen's vertical centre, expressed in this container's coordinates.
    /// Needed because the container is inset by the bar and the agent bar while
    /// the OSD lives in its own full-screen overlay window and centres on the
    /// screen — anchoring the trigger zones to `parent.verticalCenter` would
    /// offset them from the cards they summon by half the difference.
    readonly property real screenCentreY: height / 2 + (agentBar.implicitHeight - bar.implicitHeight) / 2
    readonly property alias launcher: launcher
    readonly property alias popouts: popouts
    readonly property alias utilities: utilities
    readonly property alias sidebar: sidebar
    readonly property alias clipboard: clipboard
    readonly property alias askpass: askpass
    readonly property alias recorder: recorder
    readonly property alias calculator: calculator
    readonly property alias packages: packages
    readonly property alias videoTrim: videoTrim

    anchors.fill: parent
    anchors.leftMargin: Config.border.sideThickness
    anchors.rightMargin: Config.border.sideThickness
    anchors.topMargin: bar.implicitHeight
    anchors.bottomMargin: agentBar.implicitHeight

    // Invisible placeholders — the OSD lives in its own overlay window
    // (OsdOverlay.qml). These only define the right-edge hover zones that
    // Interactions.qml tests; inRightPanel reads x, y and height.
    //
    // The strip is split at the screen's vertical centre so each metric has its
    // own destination: volume above, brightness below. Both halves come from the
    // single Config.osd.triggerHeight, which also sets how far each card sits
    // from centre — see the note on that property before changing either.
    /// A zone is only as wide as it is useful. Width is what carves it out of the
    /// drawers input mask, so a zone for a switched-off metric would go on taking
    /// those pixels away from the window underneath while doing nothing at all.
    /// The floor of 1 also guards the documented "must be greater than zero" on
    /// triggerWidth, which nothing else enforces — a 0 there restores the exact
    /// silent failure this trigger was just rescued from.
    component OsdTriggerZone: Item {
        required property bool zoneEnabled

        implicitWidth: zoneEnabled ? Math.max(1, Config.osd.triggerWidth) : 0
        implicitHeight: Config.osd.triggerHeight / 2

        anchors.right: parent.right
        anchors.rightMargin: sidebar.width
    }

    OsdTriggerZone {
        id: osdVolume

        zoneEnabled: Config.osd.enabled
        y: root.screenCentreY - height
    }

    OsdTriggerZone {
        id: osdBrightness

        zoneEnabled: Config.osd.enabled && Config.osd.enableBrightness
        y: root.screenCentreY
    }

    // Session menu lives in modules/session/SessionOverlay.qml (mounted from
    // shell.qml) on WlrLayer.Overlay so it appears above fullscreen clients.

    Launcher.Wrapper {
        id: launcher

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    ClipboardModule.Wrapper {
        id: clipboard

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: launcher.height > 0 ? launcher.height + Appearance.spacing.large : 0
    }

    // Maximized image preview for the clipboard's Images tab. Sized to fill
    // the entire inter-bar area when active so the screenshot can dominate
    // without covering the top bar / agentBar. Lives at this level (not inside
    // the clipboard drawer) because the drawer's bounds are too small.
    // Declared AFTER clipboard so it renders on top in z-order.
    ClipboardModule.ImagePreview {
        id: clipboardPreview

        clipState: clipboard.clipState

        // Only anchor the corner — width/height are bound inside the component
        // so they collapse to 0 when closed (mask-region hygiene). Setting
        // anchors.fill here would override those bindings.
        anchors.top: parent.top
        anchors.left: parent.left
    }

    CalculatorModule.Wrapper {
        id: calculator

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Stack above launcher and clipboard if they are open
        anchors.bottomMargin: {
            let margin = 0;
            if (launcher.height > 0)
                margin += launcher.height + Appearance.spacing.large;
            if (clipboard.height > 0)
                margin += clipboard.height + Appearance.spacing.large;
            return margin;
        }
    }

    Askpass.Wrapper {
        id: askpass

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    RecorderModule.Wrapper {
        id: recorder

        screen: root.screen
        visibilities: root.visibilities

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    PackagesModule.Wrapper {
        id: packages

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    VideoTrimModule.Wrapper {
        id: videoTrim

        screen: root.screen

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    BarPopouts.Wrapper {
        id: popouts

        screen: root.screen

        x: {
            if (popouts._detachedFull)
                return 0;

            const off = currentCenter - Config.border.sideThickness - nonAnimWidth / 2;
            const diff = root.width - Math.floor(off + nonAnimWidth);
            if (diff < 0)
                return off + diff;
            return Math.max(off, 0);
        }
        y: 0

        Component.onCompleted: {
            Visibilities.popouts.set(root.screen, popouts);
            Visibilities.popoutsVersion++;
        }
        Component.onDestruction: {
            if (Visibilities.popouts.get(root.screen) === popouts) {
                Visibilities.popouts.delete(root.screen);
                Visibilities.popoutsVersion++;
            }
        }
    }

    Utilities.Wrapper {
        id: utilities

        visibilities: root.visibilities
        sidebar: sidebar
        popouts: popouts

        anchors.bottom: parent.bottom
        anchors.right: parent.right

        Component.onCompleted: {
            Visibilities.utilitiesPanels.set(root.screen, utilities);
            Visibilities.utilitiesPanelsVersion++;
        }
        Component.onDestruction: {
            if (Visibilities.utilitiesPanels.get(root.screen) === utilities) {
                Visibilities.utilitiesPanels.delete(root.screen);
                Visibilities.utilitiesPanelsVersion++;
            }
        }
    }

    Utilities.RecordingIndicator {
        id: recordingIndicator

        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Appearance.padding.normal
    }

    Sidebar.Wrapper {
        id: sidebar

        visibilities: root.visibilities
        panels: root

        anchors.top: parent.top
        anchors.bottom: utilities.top
        anchors.right: parent.right
    }
}
