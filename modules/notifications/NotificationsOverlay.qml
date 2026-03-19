pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

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

            Region {
                id: contentRegion
                x: notifContent.visible ? notifContent.x : 0
                y: notifContent.visible ? notifContent.y : 0
                width: notifContent.visible ? notifContent.width : 0
                height: notifContent.visible ? notifContent.height : 0
            }

            // Bar reference for positioning below the bar.
            // Captured once at startup — bar objects are stable after creation.
            property Item barRef: null
            Component.onCompleted: barRef = Visibilities.bars.get(modelData) ?? null
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
                visible: content.implicitHeight > 0

                // Background with shadow and transparency.
                // Two-layer approach matches OsdOverlay / Drawers.qml: outer layer applies
                // transparency + shadow, inner layer renders shapes at full opacity.
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    opacity: Colours.transparency.enabled ? Colours.transparency.base : 1
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 15
                        shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.7)
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        opacity: Colours.generalBackgroundAlpha

                        Rectangle {
                            anchors.fill: parent
                            color: Colours.generalBackgroundOpaque
                            radius: Config.border.rounding
                        }
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
