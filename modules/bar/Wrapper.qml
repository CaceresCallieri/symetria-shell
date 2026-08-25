pragma ComponentBehavior: Bound

import qs.components
import qs.config
import qs.services
import "popouts" as BarPopouts
import Quickshell
import QtQuick

Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property BarPopouts.Wrapper popouts
    required property bool disabled

    // FORM axis. "border" reproduces the historical rule — the bar insets its
    // content so it floats as a detached island below the screen edge, with a
    // floor of padding.smaller so the island never collapses even when the
    // border is configured to nothing. "flush" drops the inset entirely so bar
    // content sits hard against the top of the screen; combined with
    // Theme.layout.barTopBleed the plates then continue past it.
    readonly property int padding: Theme.layout.barPaddingMode === "flush" ? 0 : Math.max(Appearance.padding.smaller, Config.border.thickness)
    readonly property int contentHeight: Config.bar.sizes.innerWidth + padding * 2
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || visibilities.bar) ? contentHeight : Config.border.thickness
    readonly property bool shouldBeVisible: !disabled && (Config.bar.persistent || visibilities.bar || isHovered)
    property bool isHovered

    function closeTray(): void {
        content.item?.closeTray();
    }

    function checkPopout(x: real): void {
        content.item?.checkPopout(x);
    }

    function handleWheel(x: real, angleDelta: point): void {
        content.item?.handleWheel(x, angleDelta);
    }

    function openNamedPopout(popoutName: string): bool {
        return content.item?.openNamedPopout(popoutName) ?? false;
    }

    visible: height > Config.border.thickness
    implicitHeight: Config.border.thickness

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitHeight: root.contentHeight
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitHeight"
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitHeight"
                easing.bezierCurve: Appearance.anim.curves.emphasized
            }
        }
    ]

    Loader {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        active: root.shouldBeVisible || root.visible

        sourceComponent: Bar {
            height: root.contentHeight
            screen: root.screen
            visibilities: root.visibilities
            popouts: root.popouts
        }
    }
}
