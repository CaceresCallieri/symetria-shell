pragma ComponentBehavior: Bound

import qs.components
import qs.config
import qs.services
import Quickshell
import QtQuick

/// Animation wrapper for STT drawer.
///
/// Each job card independently slides down (show) and up (hide), preserving
/// the same reveal-from-top pattern used by Askpass.  The wrapper itself is a
/// passive container that tracks the Row's natural dimensions — no animation
/// logic at this level.  The TopHangingBackground in Backgrounds.qml reads
/// wrapper.width / wrapper.height and auto-adapts.
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property var panels

    // Hidden when merge mode is active — bar embed (SttBarEmbed) takes over.
    visible: height > 0 && !AgentService.mergeActive
    implicitHeight: AgentService.mergeActive ? 0 : mainColumn.implicitHeight
    implicitWidth: mainColumn.implicitWidth

    Column {
        id: mainColumn

        // Anchor content to BOTTOM of wrapper so it reveals from top-down
        // as each delegate's height grows.
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0

        Row {
            id: jobsRow

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Appearance.spacing.normal

            Repeater {
                model: ScriptModel {
                    values: SttService.jobs
                }

                Item {
                    id: jobDelegate

                    required property SttService.SttJob modelData
                    required property int index

                    // Target height for the show animation.  Updated reactively
                    // via onImplicitHeightChanged on Content — NOT captured in
                    // Component.onCompleted (which fires before the QML polish
                    // phase where ColumnLayout computes implicitHeight).
                    property real contentHeight: 0

                    // Guard: only react to Content height changes during the
                    // initial reveal.  Set to false by showAnim's ScriptAction.
                    property bool initialShow: true

                    implicitWidth: jobContent.implicitWidth
                    implicitHeight: 0
                    clip: true

                    Content {
                        id: jobContent
                        anchors.bottom: parent.bottom
                        screen: root.screen
                        visibilities: root.visibilities
                        job: jobDelegate.modelData
                    }

                    // ── Capture contentHeight reactively after polish ─────────
                    // Component.onCompleted fires BEFORE ColumnLayout polishes,
                    // so implicitHeight is wrong at that point.  This handler
                    // fires AFTER polish, giving us the correct final height.
                    //
                    // If Content's height grows (e.g., FadeTransitions becoming
                    // visible), we stop the in-flight showAnim and restart it
                    // from the current position toward the new target.
                    Connections {
                        target: jobContent

                        function onImplicitHeightChanged(): void {
                            if (!jobDelegate.initialShow) return;
                            const h = jobContent.implicitHeight;
                            if (h <= 0) return;

                            // Only grow — shrinking mid-reveal would look jarring.
                            if (h > jobDelegate.contentHeight) {
                                // Stop resets from-value to current position before restart.
                                if (showAnim.running) showAnim.stop();
                                jobDelegate.contentHeight = h;
                            }
                        }
                    }

                    // ── Show: slide down when content height is known ─────────
                    onContentHeightChanged: {
                        if (contentHeight > 0 && !showAnim.running)
                            showAnim.start();
                    }

                    SequentialAnimation {
                        id: showAnim

                        Anim {
                            target: jobDelegate
                            property: "implicitHeight"
                            to: jobDelegate.contentHeight
                            duration: Appearance.anim.durations.expressiveDefaultSpatial
                            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                        }
                        ScriptAction {
                            script: {
                                jobDelegate.initialShow = false;
                                jobContent.enableHeightTransition = true;
                                jobDelegate.implicitHeight = Qt.binding(() => jobContent.implicitHeight);
                            }
                        }
                    }

                    // ── Hide: slide up when job is closing ────────────────────
                    Connections {
                        target: jobDelegate.modelData

                        function onClosingChanged(): void {
                            if (jobDelegate.modelData.closing) {
                                jobDelegate.initialShow = false;
                                showAnim.stop();
                                hideAnim.start();
                            }
                        }
                    }

                    SequentialAnimation {
                        id: hideAnim

                        ScriptAction {
                            // Break the live binding so height can animate freely.
                            script: jobDelegate.implicitHeight = jobDelegate.implicitHeight
                        }
                        Anim {
                            target: jobDelegate
                            property: "implicitHeight"
                            to: 0
                            duration: Appearance.anim.durations.normal  // shorter than show — hides should feel snappy
                            easing.bezierCurve: Appearance.anim.curves.emphasized
                        }
                    }
                }
            }
        }

        FadeTransition {
            show: SttService.vocabHintsVisible && SttService.active
            anchors.horizontalCenter: parent.horizontalCenter

            VocabularyHints {}
        }
    }
}
