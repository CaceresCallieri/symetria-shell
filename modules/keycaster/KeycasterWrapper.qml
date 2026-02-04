pragma ComponentBehavior: Bound

import qs.components
import qs.config
import qs.services
import Quickshell
import QtQuick

/// Animation wrapper for standalone Keycaster floating overlay.
///
/// Handles slide-up animation from bottom of screen.
/// Content is anchored to top so it reveals bottom-up as wrapper height grows.
Item {
    id: root

    required property ShellScreen screen

    // Direct binding to Visibilities service (no longer passed from drawer system)
    // Uses getForMonitor() which is reactive via screensVersion counter
    readonly property var visibilities: Visibilities.getForMonitor(Hypr.monitorFor(screen))
    readonly property bool shouldBeActive: (visibilities?.keycaster ?? false) && (Config.keycaster?.enabled ?? true)
    property int contentHeight

    visible: height > 0
    implicitHeight: 0
    implicitWidth: content.implicitWidth

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            timer.stop();
            hideAnim.stop();
            showAnim.start();
            // Sync service state with visibility
            KeycasterService.active = true;
        } else {
            showAnim.stop();
            hideAnim.start();
            KeycasterService.active = false;
        }
    }

    SequentialAnimation {
        id: showAnim

        Anim {
            target: root
            property: "implicitHeight"
            to: root.contentHeight
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
        ScriptAction {
            script: root.implicitHeight = Qt.binding(() => content.implicitHeight)
        }
    }

    SequentialAnimation {
        id: hideAnim

        ScriptAction {
            // Break the binding established by showAnim to prevent binding loops
            // during the hide animation. Assigns current value without reactive binding.
            script: root.implicitHeight = root.implicitHeight
        }
        Anim {
            target: root
            property: "implicitHeight"
            to: 0
            easing.bezierCurve: Appearance.anim.curves.emphasized
        }
    }

    // Watch for config changes (e.g., enabled toggle from control center)
    Connections {
        target: Config.keycaster

        function onEnabledChanged(): void {
            // Trigger content reload to recalculate height before animation.
            // This handles the case where keycaster is enabled while already
            // "visible" via IPC toggle but hidden due to enabled=false.
            timer.start();
        }
    }

    // Content reload timer - handles config changes and initial setup.
    // Brief delay allows content to recalculate its implicit height before
    // the show animation uses that value. Without this, the animation would
    // target the old/stale height from before the config change.
    Timer {
        id: timer

        interval: Appearance.anim.durations.extraLarge

        onRunningChanged: {
            if (running && !root.shouldBeActive) {
                // Config changed while inactive: preload content invisibly
                // so height is ready when user toggles keycaster on
                content.visible = false;
                content.active = true;
            } else {
                // Update height target and ensure content stays active
                root.contentHeight = content.implicitHeight;
                content.active = Qt.binding(() => root.shouldBeActive || root.visible);
                content.visible = true;

                // Restart animation if it was interrupted by config change
                if (showAnim.running) {
                    showAnim.stop();
                    showAnim.start();
                }
            }
        }
    }

    Loader {
        id: content

        // For bottom-sliding overlay: anchor content to TOP of wrapper
        // so it reveals from bottom-up as wrapper height grows
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        visible: false
        active: false
        Component.onCompleted: timer.start()

        sourceComponent: Content {
            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }
}
