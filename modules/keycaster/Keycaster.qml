pragma ComponentBehavior: Bound

import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

/// Keycaster - Standalone floating overlay displaying keyboard events.
///
/// Unlike drawer-based modules (launcher, clipboard), Keycaster renders in its
/// own StyledWindow that floats independently at the bottom of the screen.
/// It doesn't have union corners with the shell border.
///
/// Visibility is controlled via IPC or the Visibilities service:
///   qs -c symmetria ipc call keycaster toggle
///   qs -c symmetria ipc call drawers toggle keycaster  (legacy, still works)
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool shouldShow: wrapper.visible

            screen: modelData
            name: "keycaster"

            // Passive overlay - no exclusion, no keyboard focus
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Full-screen transparent window, content positioned internally
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Always pass clicks through - keycaster is display-only
            mask: Region {}

            KeycasterWrapper {
                id: wrapper

                screen: win.modelData

                // Dynamic margins from Hyprland gaps_out, with extra inset so the
                // keycaster sits slightly inside the window area rather than at the edge.
                // Horizontal/vertical insets differ to compensate for the pill shape's
                // optical asymmetry (wide rounded rect looks closer to the right edge).
                readonly property string gapsRaw: Hypr.options["general:gaps_out"] ?? ""
                readonly property var gapsParts: gapsRaw.toString().split(" ").map(Number).filter(n => !isNaN(n))
                readonly property real gapRight: gapsParts.length >= 2 ? gapsParts[1] : (gapsParts.length === 1 ? gapsParts[0] : -1)
                readonly property real gapBottom: gapsParts.length >= 3 ? gapsParts[2] : (gapsParts.length === 1 ? gapsParts[0] : -1)

                readonly property real fallbackMargin: Config.border.thickness + Appearance.spacing.large
                readonly property real horizontalInset: 20
                readonly property real verticalInset: 12

                anchors.right: parent.right
                anchors.rightMargin: gapRight >= 0 ? gapRight + horizontalInset : fallbackMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: gapBottom >= 0 ? gapBottom + verticalInset : fallbackMargin
            }
        }
    }

    IpcHandler {
        target: "keycaster"

        function toggle(): void {
            const vis = Visibilities.getForActive();
            if (!vis) {
                console.error("[Keycaster] Failed to toggle: no visibility object for active screen");
                return;
            }
            vis.keycaster = !vis.keycaster;
        }

        function show(): void {
            const vis = Visibilities.getForActive();
            if (!vis) {
                console.error("[Keycaster] Failed to show: no visibility object for active screen");
                return;
            }
            vis.keycaster = true;
        }

        function hide(): void {
            const vis = Visibilities.getForActive();
            if (!vis) {
                console.error("[Keycaster] Failed to hide: no visibility object for active screen");
                return;
            }
            vis.keycaster = false;
        }

        function isVisible(): bool {
            return Visibilities.getForActive()?.keycaster ?? false;
        }
    }
}
