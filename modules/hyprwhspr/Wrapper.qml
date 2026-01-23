pragma ComponentBehavior: Bound

import qs.components
import qs.config
import Quickshell
import QtQuick

/// Animation wrapper for HyprWhspr drawer.
///
/// Handles slide-down animation from top of screen, similar to Askpass.
/// Content is anchored to bottom so it reveals top-down as height grows.
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property var panels

    readonly property bool shouldBeActive: visibilities.hyprwhspr && Config.hyprwhspr.enabled
    property int contentHeight

    visible: height > 0
    implicitHeight: 0
    implicitWidth: content.implicitWidth

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            timer.stop();
            hideAnim.stop();
            showAnim.start();
        } else {
            showAnim.stop();
            hideAnim.start();
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

    Connections {
        target: Config.hyprwhspr

        function onEnabledChanged(): void {
            timer.start();
        }
    }

    Timer {
        id: timer

        interval: Appearance.anim.durations.extraLarge
        onRunningChanged: {
            if (running && !root.shouldBeActive) {
                content.visible = false;
                content.active = true;
            } else {
                root.contentHeight = content.implicitHeight;
                content.active = Qt.binding(() => root.shouldBeActive || root.visible);
                content.visible = true;
                if (showAnim.running) {
                    showAnim.stop();
                    showAnim.start();
                }
            }
        }
    }

    Loader {
        id: content

        // For top-sliding drawer: anchor content to BOTTOM of wrapper
        // so it reveals from top-down as wrapper height grows
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        visible: false
        active: false
        Component.onCompleted: timer.start()

        sourceComponent: Content {
            screen: root.screen
            visibilities: root.visibilities

            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }
}
