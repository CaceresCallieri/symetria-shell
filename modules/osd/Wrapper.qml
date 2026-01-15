pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

Item {
    id: root

    required property ShellScreen screen
    required property var visibilities
    property bool hovered
    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    readonly property bool shouldBeActive: visibilities.osd && Config.osd.enabled && !(visibilities.utilities && Config.utilities.enabled)

    property real volume
    property bool muted
    property real sourceVolume
    property bool sourceMuted
    property real brightness

    function show(): void {
        visibilities.osd = true;
        autoHideTimer.restart();
    }

    Component.onCompleted: {
        volume = Audio.volume;
        muted = Audio.muted;
        sourceVolume = Audio.sourceVolume;
        sourceMuted = Audio.sourceMuted;
        brightness = root.monitor?.brightness ?? 0;
    }

    visible: width > 0
    implicitWidth: 0
    implicitHeight: content.implicitHeight

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
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
            property: "implicitWidth"
            to: content.implicitWidth
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
        ScriptAction {
            script: root.implicitWidth = Qt.binding(() => content.implicitWidth)
        }
    }

    SequentialAnimation {
        id: hideAnim

        ScriptAction {
            // Break the binding established by showAnim to prevent binding loops
            // during the hide animation. Assigns current value without reactive binding.
            script: root.implicitWidth = root.implicitWidth
        }
        Anim {
            target: root
            property: "implicitWidth"
            to: 0
            duration: Appearance.anim.durations.normal
            easing.bezierCurve: Appearance.anim.curves.emphasized
        }
    }

    Connections {
        target: Audio

        function onMutedChanged(): void {
            root.show();
            root.muted = Audio.muted;
        }

        function onVolumeChanged(): void {
            root.show();
            root.volume = Audio.volume;
        }

        function onSourceMutedChanged(): void {
            root.show();
            root.sourceMuted = Audio.sourceMuted;
        }

        function onSourceVolumeChanged(): void {
            root.show();
            root.sourceVolume = Audio.sourceVolume;
        }
    }

    Connections {
        target: root.monitor

        function onBrightnessChanged(): void {
            root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }
    }

    // OSD auto-hides after delay unless hovered (unique to OSD, other panels stay visible)
    Timer {
        id: autoHideTimer

        interval: Config.osd.hideDelay
        onTriggered: {
            if (!root.hovered)
                root.visibilities.osd = false;
        }
    }

    Loader {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        Component.onCompleted: active = Qt.binding(() => root.shouldBeActive || root.visible)

        sourceComponent: Content {
            monitor: root.monitor
            visibilities: root.visibilities
            volume: root.volume
            muted: root.muted
            sourceVolume: root.sourceVolume
            sourceMuted: root.sourceMuted
            brightness: root.brightness
        }
    }
}
