pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick

/// Standalone notifications overlay on WlrLayer.Overlay.
///
/// Renders above fullscreen windows (unlike the former drawer-based notifications on WlrLayer.Top).
/// Visibility is content-driven: appears when popup notifications exist, disappears when they don't.
/// Each notification manages its own expiry timer — no global auto-hide needed.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "notifications-overlay"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Click-through when no notifications, content area when visible.
            // Always bound to contentRegion so geometry changes re-evaluate the mask.
            mask: contentRegion

            // True when popup notifications exist — drives mask and visibility.
            readonly property bool hasContent: content.implicitHeight > 0

            Region {
                id: contentRegion
                x: win.hasContent ? notifContent.x : 0
                y: win.hasContent ? notifContent.y : 0
                width: win.hasContent ? notifContent.width : 0
                height: win.hasContent ? notifContent.height : 0
            }

            // Bar reference for positioning below the bar.
            // Reactive via barsVersion — resolves correctly even when bars register
            // after this overlay (onCompleted order is not guaranteed across Variants).
            readonly property Item barRef: {
                void Visibilities.barsVersion;
                return Visibilities.bars.get(modelData) ?? null;
            }
            readonly property real barHeight: barRef?.implicitHeight ?? Config.border.thickness

            // Notifications content — top-right aligned, below bar
            Item {
                id: notifContent

                anchors.top: parent.top
                anchors.topMargin: win.barHeight
                anchors.right: parent.right
                anchors.rightMargin: Config.border.thickness

                width: content.implicitWidth
                height: content.implicitHeight
                // Slide + fade: right-to-left on show, left-to-right on hide
                opacity: win.hasContent ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    Anim {}
                }

                transform: Translate {
                    x: win.hasContent ? 0 : notifContent.width + Config.border.thickness
                    Behavior on x {
                        Anim {}
                    }
                }

                Content {
                    id: content

                    anchors.fill: parent
                }
            }
        }
    }
}
