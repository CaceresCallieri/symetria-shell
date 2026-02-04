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

            // Empty mask when not visible (passes all input through)
            mask: shouldShow ? null : emptyRegion

            Region {
                id: emptyRegion
            }

            KeycasterWrapper {
                id: wrapper

                screen: win.modelData

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Config.border.thickness + Appearance.spacing.large
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
