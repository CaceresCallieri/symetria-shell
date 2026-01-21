pragma ComponentBehavior: Bound

import qs.components
import qs.components.filedialog
import qs.config
import qs.utils
import Symmetria
import Quickshell
import QtQuick

Item {
    id: root

    required property PersistentProperties visibilities
    readonly property PersistentProperties dashState: PersistentProperties {
        property int currentTab
        property date currentDate: new Date()

        reloadableId: "dashboardState"
    }
    readonly property FileDialog facePicker: FileDialog {
        title: qsTr("Select a profile picture")
        filterLabel: qsTr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                Quickshell.execDetached(["notify-send", "-a", "symmetria-shell", "-u", "low", "-h", `STRING:image-path:${path}`, "Profile picture changed", `Profile picture changed to ${Paths.shortenHome(path)}`]);
            else
                Quickshell.execDetached(["notify-send", "-a", "symmetria-shell", "-u", "critical", "Unable to change profile picture", `Failed to change profile picture to ${Paths.shortenHome(path)}`]);
        }
    }

    readonly property bool shouldBeActive: visibilities.dashboard && Config.dashboard.enabled
    readonly property real nonAnimHeight: shouldBeActive ? (content.item?.nonAnimHeight ?? 0) : 0

    visible: height > 0
    implicitHeight: 0
    implicitWidth: content.implicitWidth

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            if (deferredLoadTimer.running) {
                deferredLoadTimer.triggered();
                deferredLoadTimer.stop();
            }
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
            to: content.implicitHeight
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

    // Defer dashboard content loading to improve shell startup performance.
    // Content loads after extraLarge duration to avoid blocking initial render.
    Timer {
        id: deferredLoadTimer

        running: true
        interval: Appearance.anim.durations.extraLarge
        onTriggered: {
            // Enable lazy loading: keep content loaded only while visible
            content.active = Qt.binding(() => root.shouldBeActive || root.visible);
            content.visible = true;
        }
    }

    Loader {
        id: content

        anchors.left: parent.left
        anchors.bottom: parent.bottom

        visible: false
        active: true

        sourceComponent: Content {
            visibilities: root.visibilities
            state: root.dashState
            facePicker: root.facePicker
        }
    }
}
