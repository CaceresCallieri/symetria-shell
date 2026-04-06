pragma ComponentBehavior: Bound

import qs.components
import qs.config
import Quickshell
import QtQuick

/// Reusable vertical-slide drawer with deferred loading, show/hide animation,
/// and Loader lifecycle management. Used by launcher, clipboard, calculator,
/// packages, and askpass drawers.
///
/// Consumers provide `shouldBeActive`, `maxHeight`, and `contentComponent`.
/// The base handles animation, Timer-based preloading, and Loader active/visible state.
Item {
    id: root

    // --- Required from consumer ---
    required property bool shouldBeActive
    required property real maxHeight
    required property Component contentComponent

    // --- Optional customization ---
    /// When true (default), content anchors to parent.top and reveals bottom-up.
    /// When false, content anchors to parent.bottom and reveals top-down.
    property bool anchorToTop: true
    /// When true (default), clamp contentHeight to maxHeight.
    /// When false, use raw content implicitHeight (e.g. askpass has no maxHeight constraint).
    property bool clampToMaxHeight: true

    // --- Read-only output ---
    readonly property Item contentItem: content.item
    readonly property bool contentActive: content.active

    // --- Signals ---
    /// Emit from consumer when config changes that affect content size
    /// (e.g. Config.launcher.maxShownChanged, Config.calculator.maxHistoryChanged).
    /// Triggers the deferred reload timer.
    signal configChanged()

    // --- Internal state ---
    property int contentHeight

    visible: height > 0
    implicitHeight: 0
    implicitWidth: content.implicitWidth

    onMaxHeightChanged: timer.start()
    onConfigChanged: timer.start()

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

    Timer {
        id: timer

        interval: Appearance.anim.durations.extraLarge
        onRunningChanged: {
            if (running && !root.shouldBeActive) {
                content.visible = false;
                content.active = true;
            } else {
                root.contentHeight = root.clampToMaxHeight
                    ? Math.min(root.maxHeight, content.implicitHeight)
                    : content.implicitHeight;
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

        anchors.top: root.anchorToTop ? parent.top : undefined
        anchors.bottom: root.anchorToTop ? undefined : parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        visible: false
        active: false
        Component.onCompleted: timer.start()

        sourceComponent: root.contentComponent

        // Set initial contentHeight when content is first created.
        // Equivalent to the original Content { Component.onCompleted: root.contentHeight = implicitHeight }
        // pattern — fires at the same lifecycle point (after item creation, before polish).
        onItemChanged: {
            if (item) {
                root.contentHeight = root.clampToMaxHeight
                    ? Math.min(root.maxHeight, content.implicitHeight)
                    : content.implicitHeight;
            }
        }
    }
}
