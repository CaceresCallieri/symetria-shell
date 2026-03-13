pragma ComponentBehavior: Bound

import qs.components
import qs.config
import qs.services
import Quickshell
import QtQuick

/// Animation wrapper for STT drawer.
///
/// Handles slide-down animation from top of screen, similar to Askpass.
/// Displays multiple job cards via Row + Repeater when pipeline chaining is active.
/// Content is anchored to bottom so it reveals top-down as height grows.
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property var panels

    readonly property bool shouldBeActive: visibilities.stt && Config.stt.enabled
    property int contentHeight

    visible: height > 0
    implicitHeight: 0
    implicitWidth: jobsRow.implicitWidth

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            // If the pre-load timer is still running, finalize immediately
            // so content becomes visible before the show animation starts.
            if (timer.running) {
                timer.stop();
                timer.finalize();
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
            to: root.contentHeight
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
        ScriptAction {
            script: root.implicitHeight = Qt.binding(() => jobsRow.implicitHeight)
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
        target: Config.stt

        function onEnabledChanged(): void {
            timer.startPreload();
        }
    }

    Timer {
        id: timer

        interval: Appearance.anim.durations.extraLarge

        /// Pre-load content invisibly so it can measure its layout.
        /// If the drawer is already active, skip the timer and finalize immediately.
        function startPreload(): void {
            if (!root.shouldBeActive) {
                jobsRow.visible = false;
                start();
            } else {
                finalize();
            }
        }

        /// Finalize layout after pre-load: capture content height, restore
        /// visibility, and re-sync the show animation if needed.
        function finalize(): void {
            root.contentHeight = jobsRow.implicitHeight;
            jobsRow.visible = true;
            if (showAnim.running) {
                showAnim.stop();
                showAnim.start();
            }
        }

        onTriggered: finalize()
    }

    Row {
        id: jobsRow

        // For top-sliding drawer: anchor content to BOTTOM of wrapper
        // so it reveals from top-down as wrapper height grows
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Appearance.spacing.normal

        visible: false
        Component.onCompleted: timer.startPreload()

        Repeater {
            model: ScriptModel {
                values: SttService.jobs
            }

            Item {
                id: jobDelegate

                required property SttService.SttJob modelData
                required property int index

                // Animated removal: width shrinks to 0, content fades
                implicitWidth: modelData.closing ? 0 : jobContent.implicitWidth
                implicitHeight: jobContent.implicitHeight
                clip: true
                opacity: modelData.closing ? 0 : 1

                Behavior on implicitWidth { Anim {} }
                Behavior on opacity { Anim {} }

                Content {
                    id: jobContent
                    screen: root.screen
                    visibilities: root.visibilities
                    job: jobDelegate.modelData
                }
            }
        }
    }
}
