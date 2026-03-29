import qs.components
import qs.config
// Heavy module imports removed — compiled on-demand via Loader.setSource()
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities as Utilities
import qs.modules.utilities.toasts as Toasts
import qs.modules.sidebar as Sidebar
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
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popouts
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar
    readonly property alias clipboard: clipboard
    readonly property alias askpass: askpass
    readonly property alias stt: stt
    readonly property alias calculator: calculator
    readonly property alias packages: packages

    anchors.fill: parent
    anchors.margins: Config.border.thickness
    anchors.topMargin: bar.implicitHeight
    anchors.bottomMargin: agentBar.implicitHeight

    // ── Deferred panel activation ───────────────────────────────────────
    // Each handler fires setSource exactly once (guarded by Loader.Null),
    // then the panel stays alive — subsequent toggles use the Wrapper's
    // own show/hide animation.
    Connections {
        target: root.visibilities

        function onSessionChanged(): void {
            if (root.visibilities.session && Config.session.enabled && session.status === Loader.Null)
                session.setSource(Qt.resolvedUrl("../session/Wrapper.qml"), {
                    visibilities: root.visibilities,
                    panels: root,
                    clip: Qt.binding(() => sidebar.width > 0)
                });
        }

        function onLauncherChanged(): void {
            if (root.visibilities.launcher && Config.launcher.enabled && launcher.status === Loader.Null)
                launcher.setSource(Qt.resolvedUrl("../launcher/Wrapper.qml"), {
                    screen: root.screen,
                    visibilities: root.visibilities,
                    panels: root
                });
        }

        function onClipboardChanged(): void {
            if (root.visibilities.clipboard && Config.clipboard.enabled && clipboard.status === Loader.Null)
                clipboard.setSource(Qt.resolvedUrl("../clipboard/Wrapper.qml"), {
                    screen: root.screen,
                    visibilities: root.visibilities,
                    panels: root
                });
        }

        function onCalculatorChanged(): void {
            if (root.visibilities.calculator && Config.calculator.enabled && calculator.status === Loader.Null)
                calculator.setSource(Qt.resolvedUrl("../calculator/Wrapper.qml"), {
                    screen: root.screen,
                    visibilities: root.visibilities,
                    panels: root
                });
        }

        function onDashboardChanged(): void {
            if (root.visibilities.dashboard && Config.dashboard.enabled && dashboard.status === Loader.Null)
                dashboard.setSource(Qt.resolvedUrl("../dashboard/Wrapper.qml"), {
                    visibilities: root.visibilities
                });
        }

        function onAskpassChanged(): void {
            if (root.visibilities.askpass && Config.askpass.enabled && askpass.status === Loader.Null)
                askpass.setSource(Qt.resolvedUrl("../askpass/Wrapper.qml"), {
                    screen: root.screen,
                    visibilities: root.visibilities,
                    panels: root
                });
        }

        function onSttChanged(): void {
            if (root.visibilities.stt && Config.stt.enabled && stt.status === Loader.Null)
                stt.setSource(Qt.resolvedUrl("../stt/Wrapper.qml"), {
                    screen: root.screen,
                    visibilities: root.visibilities,
                    panels: root
                });
        }

        function onPackagesChanged(): void {
            if (root.visibilities.packages && Config.packages.enabled && packages.status === Loader.Null)
                packages.setSource(Qt.resolvedUrl("../packages/Wrapper.qml"), {
                    screen: root.screen,
                    visibilities: root.visibilities,
                    panels: root
                });
        }
    }

    // ── Eager panels (lightweight / always needed) ──────────────────────

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
        anchors.rightMargin: session.width + sidebar.width
    }

    BarPopouts.Wrapper {
        id: popouts

        screen: root.screen

        x: {
            if (popouts._detachedFull)
                return 0;

            const off = currentCenter - Config.border.thickness - nonAnimWidth / 2;
            const diff = root.width - Math.floor(off + nonAnimWidth);
            if (diff < 0)
                return off + diff;
            return Math.max(off, 0);
        }
        y: 0
    }

    Utilities.Wrapper {
        id: utilities

        visibilities: root.visibilities
        sidebar: sidebar
        popouts: popouts

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Utilities.RecordingIndicator {
        id: recordingIndicator

        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Appearance.padding.normal
    }

    Toasts.Toasts {
        id: toasts

        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.rightMargin: Appearance.padding.normal
        anchors.bottomMargin: Appearance.padding.normal + (recordingIndicator.active ? recordingIndicator.implicitHeight + Appearance.spacing.small : 0)

        Behavior on anchors.bottomMargin {
            Anim {}
        }
    }

    Sidebar.Wrapper {
        id: sidebar

        visibilities: root.visibilities
        panels: root

        anchors.top: parent.top
        anchors.bottom: utilities.top
        anchors.right: parent.right
    }

    // ── Lazy-loaded panels (deferred via Loader.setSource) ──────────────
    // visible defaults to false so sidebar.visible checks in toast/indicator
    // anchoring work correctly when panels are unloaded.

    Loader {
        id: session
        visible: item?.visible ?? false
        asynchronous: true

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width
    }

    Loader {
        id: launcher
        visible: item?.visible ?? false
        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    Loader {
        id: clipboard
        visible: item?.visible ?? false
        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: launcher.height > 0 ? launcher.height + Appearance.spacing.large : 0
    }

    Loader {
        id: calculator
        visible: item?.visible ?? false
        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: {
            let margin = 0;
            if (launcher.height > 0)
                margin += launcher.height + Appearance.spacing.large;
            if (clipboard.height > 0)
                margin += clipboard.height + Appearance.spacing.large;
            return margin;
        }
    }

    // DISABLED: Dashboard panel is disabled and slated for removal.
    Loader {
        id: dashboard
        visible: item?.visible ?? false
        asynchronous: true

        anchors.left: parent.left
        anchors.bottom: parent.bottom
    }

    Loader {
        id: askpass
        visible: item?.visible ?? false
        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    Loader {
        id: stt
        visible: item?.visible ?? false
        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    Loader {
        id: packages
        visible: item?.visible ?? false
        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }
}
