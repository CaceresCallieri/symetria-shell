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

                // Position at 2× Hyprland gaps_out from screen edge: one gap
                // for the window margin, one more for equal inset inside the
                // client area. Parses CSS shorthand "top right bottom left".
                readonly property string gapsRaw: Hypr.options["general:gaps_out"] ?? ""
                readonly property var gapsParts: gapsRaw.toString().split(" ").filter(s => s !== "").map(Number).filter(n => !isNaN(n))
                readonly property real gapRight: gapsParts.length >= 2 ? gapsParts[1] : (gapsParts.length === 1 ? gapsParts[0] : -1)
                readonly property real gapBottom: gapsParts.length >= 3 ? gapsParts[2] : (gapsParts.length === 1 ? gapsParts[0] : -1)

                readonly property real fallbackMargin: Config.border.thickness + Appearance.spacing.large

                // Extra horizontal compensation for optical asymmetry — the pill's
                // wide bottom edge makes the bottom gap appear larger than the right.
                readonly property real horizontalCompensation: 6

                anchors.right: parent.right
                anchors.rightMargin: gapRight >= 0 ? gapRight * 2 + horizontalCompensation : fallbackMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: gapBottom >= 0 ? gapBottom * 2 : fallbackMargin
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
