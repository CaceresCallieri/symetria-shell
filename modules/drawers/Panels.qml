import qs.components
import qs.config
import qs.services
import qs.modules.session as Session
import qs.modules.launcher as Launcher
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities as Utilities
import qs.modules.sidebar as Sidebar
import qs.modules.clipboard as ClipboardModule
import qs.modules.askpass as Askpass
import qs.modules.recorder as RecorderModule
import qs.modules.calculator as CalculatorModule
import qs.modules.packages as PackagesModule
import Quickshell
import QtQuick

Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property Item bar
    required property Item agentBar

    readonly property alias osd: osd
    readonly property alias session: session
    readonly property alias launcher: launcher
    readonly property alias popouts: popouts
    readonly property alias utilities: utilities
    readonly property alias sidebar: sidebar
    readonly property alias clipboard: clipboard
    readonly property alias askpass: askpass
    readonly property alias recorder: recorder
    readonly property alias calculator: calculator
    readonly property alias packages: packages

    anchors.fill: parent
    anchors.leftMargin: Config.border.sideThickness
    anchors.rightMargin: Config.border.sideThickness
    anchors.topMargin: bar.implicitHeight
    anchors.bottomMargin: agentBar.implicitHeight

    // Invisible placeholder — OSD now lives in its own overlay window (OsdOverlay.qml).
    // This Item preserves the position reference for Interactions.qml's hover zone
    // calculation (inRightPanel uses x, y, height to define the trigger area).
    Item {
        id: osd

        implicitWidth: 0
        implicitHeight: {
            let h = Config.osd.sizes.sliderHeight;
            if (Config.osd.enableMicrophone)
                h += Config.osd.sizes.sliderHeight + Appearance.spacing.normal;
            if (Config.osd.enableBrightness)
                h += Config.osd.sizes.sliderHeight + Appearance.spacing.normal;
            return h + Appearance.padding.large * 2;
        }

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width
    }

    Session.Wrapper {
        id: session

        visibilities: root.visibilities
        panels: root

        anchors.centerIn: parent
    }

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
