pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick

/// Standalone session (power) menu overlay on WlrLayer.Overlay.
///
/// Renders above fullscreen clients (unlike the former drawer-hosted session
/// menu on WlrLayer.Top, which Wayland places below fullscreen surfaces — the
/// reason the menu was previously invisible whenever a fullscreen toplevel was
/// active). Uses the same layer-shell pattern as KillConfirmOverlay and
/// NotificationsOverlay so the menu remains usable even over fullscreen apps.
///
/// Visibility is driven by the per-screen `visibilities.session` flag stored in
/// the drawer window's PersistentProperties — the same source of truth used by
/// the bar Power button, the `session` keybind, and the `drawers toggle session`
/// IPC. We just moved the render surface; the trigger plumbing is unchanged.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "session-overlay"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // Exclusive focus so the FocusManager inside Content.qml receives
            // key events (Tab/Arrow navigation, L/P/S/R shortcuts, Escape).
            WlrLayershell.keyboardFocus: win.shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Reactively resolved per-screen visibilities — null until the
            // drawer Wrapper for this screen registers itself with Visibilities.
            readonly property var visibilities: Visibilities.getForMonitor(Hypr.monitorFor(modelData))

            readonly property bool shouldShow: visibilities?.session && Config.session.enabled

            // Window-level animated opacity drives both the scrim and the
            // centered dialog so close/open are unified.
            visible: shouldShow || dialogOpacity > 0

            property real dialogOpacity: shouldShow ? 1.0 : 0.0
            property real dialogScale: shouldShow ? 1.0 : 0.9

            Behavior on dialogOpacity {
                Anim {}
            }

            Behavior on dialogScale {
                Anim {
                    easing.bezierCurve: win.shouldShow ? Appearance.anim.curves.expressiveDefaultSpatial : Appearance.anim.curves.emphasized
                }
            }

            // Input mask: full screen while open (so click-outside dismisses
            // and the dialog's pointer events work), zero when closed (so the
            // overlay is fully click-through — critical because this window
            // sits ABOVE everything else on the Overlay layer).
            mask: inputRegion

            Region {
                id: inputRegion
                x: 0
                y: 0
                width: win.shouldShow ? win.width : 0
                height: win.shouldShow ? win.height : 0
            }

            // Full-screen scrim — now actually covers fullscreen clients
            // because we're on the Overlay layer.
            StyledRect {
                anchors.fill: parent
                opacity: win.shouldShow ? 0.5 : 0
                color: Colours.palette.m3scrim

                Behavior on opacity {
                    Anim {}
                }
            }

            // Click-outside dismissal — anywhere outside the centered dialog
            // closes the menu. Bound to the same visibilities object the
            // shortcut/IPC mutate, so external state stays consistent.
            MouseArea {
                anchors.fill: parent
                visible: win.dialogOpacity > 0
                enabled: win.shouldShow
                onClicked: {
                    if (win.visibilities)
                        win.visibilities.session = false;
                }
            }

            // Centered session menu. Loader is active during the close
            // animation so the dialog can fade/scale out before unloading.
            Loader {
                anchors.centerIn: parent
                active: win.shouldShow || win.dialogOpacity > 0

                opacity: win.dialogOpacity
                scale: win.dialogScale
                transformOrigin: Item.Center

                sourceComponent: Content {
                    visibilities: win.visibilities
                }
            }
        }
    }
}
