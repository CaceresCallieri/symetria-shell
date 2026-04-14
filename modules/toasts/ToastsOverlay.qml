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

            // Click-through when no toasts, content area when visible.
            mask: contentRegion

            readonly property bool hasContent: toasts.implicitHeight > 0

            Region {
                id: contentRegion
                x: win.hasContent ? toastContent.x : 0
                y: win.hasContent ? toastContent.y : 0
                width: win.hasContent ? toastContent.width : 0
                height: win.hasContent ? toastContent.height : 0
            }

            // Bar reference for top offset (avoid overlapping the bar).
            readonly property Item barRef: {
                void Visibilities.barsVersion;
                return Visibilities.bars.get(modelData) ?? null;
            }
            readonly property real barHeight: barRef?.implicitHeight ?? Config.border.thickness

            // Agent bar reference for bottom offset.
            readonly property Item agentBarRef: {
                void Visibilities.agentBarsVersion;
                return Visibilities.agentBars.get(modelData) ?? null;
            }
            readonly property real agentBarHeight: agentBarRef?.implicitHeight ?? Config.border.thickness

            Item {
                id: toastContent

                anchors.bottom: parent.bottom
                anchors.bottomMargin: win.agentBarHeight
                anchors.right: parent.right
                anchors.rightMargin: Config.border.thickness

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
