pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick

/// Standalone toasts overlay on WlrLayer.Overlay.
///
/// Renders above fullscreen windows (unlike the former drawer-embedded toasts on WlrLayer.Bottom).
/// Visibility is content-driven: the input mask expands when toasts exist, collapses when they don't.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "toasts-overlay"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Click-through when no visible toasts, content area when toasts are showing.
            mask: contentRegion

            readonly property bool hasContent: toasts.implicitHeight > 0

            Region {
                id: contentRegion
                x: win.hasContent ? toastContent.x : 0
                y: win.hasContent ? toastContent.y : 0
                width: win.hasContent ? toastContent.width : 0
                height: win.hasContent ? toastContent.height : 0
            }

            // Agent bar reference for bottom offset.
            // Reactive via agentBarsVersion — resolves correctly even when agent bars register
            // after this overlay (onCompleted order is not guaranteed across Variants).
            readonly property Item agentBarRef: {
                void Visibilities.agentBarsVersion;
                return Visibilities.agentBars.get(modelData) ?? null;
            }
            readonly property real agentBarHeight: agentBarRef?.implicitHeight ?? 0

            // Utilities panel reference for collision-avoidance: when the utilities
            // dashboard expands upward from the bottom-right, toasts slide UP by its
            // height so the dashboard content stays unobscured. Mirrors the
            // notifications-overlay popout pattern (see NotificationsOverlay.qml).
            //
            // Bind directly to the panel's `implicitHeight` — it's already animated
            // via the Wrapper's state transitions (0 ↔ contentHeight). NO local
            // Behavior on bottomMargin: stacking a second animation over an animated
            // source causes chase-target lag (same root cause documented in
            // NotificationsOverlay.qml). Direct binding gives frame-by-frame sync.
            readonly property Item utilitiesPanelRef: {
                void Visibilities.utilitiesPanelsVersion;
                return Visibilities.utilitiesPanels.get(modelData) ?? null;
            }
            readonly property real utilitiesHeight: utilitiesPanelRef?.implicitHeight ?? 0

            Item {
                id: toastContent

                anchors.bottom: parent.bottom
                anchors.bottomMargin: win.agentBarHeight + win.utilitiesHeight
                anchors.right: parent.right
                anchors.rightMargin: 0

                width: toasts.implicitWidth
                height: toasts.implicitHeight

                Toasts {
                    id: toasts

                    anchors.fill: parent
                }
            }
        }
    }
}
