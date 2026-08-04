// Note: No pragma ComponentBehavior: Bound here - allows WrappedLoader
// to be used by child components via PillContainer.WrappedLoader

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Base component for bar pills with a single centered RowLayout child
// (StatusIcons, TimePill, SystemPill). Uses the shared PillSurface primitive
// for background styling, so visual changes (claymorphism / flat / glass)
// happen in PillSurface.qml and propagate here for free.
//
// Usage:
//   PillContainer {
//       colour: Colours.palette.m3tertiary
//       iconContainer: content  // Optional: for popout detection
//
//       RowLayout {
//           id: content
//           // ... pill contents with PillContainer.WrappedLoader children
//       }
//   }

Item {
    id: root

    // Content color passed to child components. Single source of truth for every
    // pill's foreground — StatusIcons used to override this with m3secondary and
    // no longer does, so do not reintroduce a per-pill tone without updating the
    // note in StatusIcons.qml that explains why it was removed.
    property color colour: Colours.palette.m3tertiary

    // Popout interface: reference to the child's content container for Bar.qml's
    // detectChildPopout() integration. Uses 'property Item' instead of alias to:
    // 1. Allow null default (children without popouts can leave unset)
    // 2. Avoid parse errors when child ID doesn't exist at declaration time
    // Children with popouts should set: iconContainer: <RowLayout id>
    property Item iconContainer: null

    // Internal padding constant for pill edges
    readonly property int pillPadding: Appearance.spacing.large

    // Index of primary content child (assumes single RowLayout child)
    readonly property int primaryContentIndex: 0

    // FORM axis: the panel form grows the plate UPWARD so its top edge — border,
    // specular rim and all — falls outside the layer-shell surface and gets
    // clipped by the compositor. The plate then reads as a slab entering the
    // frame from off-screen rather than a chip sitting inside it. Bar.qml
    // bottom-aligns the row so the whole excess goes up, never down.
    //
    // Height and offset come from Theme so all three plate producers stay in
    // step — see the CONTRACT note on barPlateHeight in services/Theme.qml.
    readonly property int contentOffset: Theme.barPlateContentOffset

    implicitHeight: Theme.barPlateHeight
    implicitWidth: contentArea.children[primaryContentIndex]?.implicitWidth ?? 0

    // Default property: children declared inside PillContainer { ... } are automatically
    // reparented to contentArea via QML's default property mechanism.
    // This enables natural syntax: PillContainer { RowLayout { ... } }
    default property alias content: contentArea.data

    // Shared pill visual (claymorphism shadow + fill + border + inner gradient).
    // Defaults match the shell-wide pill appearance, so we don't pass any
    // styling overrides here.
    PillSurface {
        anchors.fill: parent
    }

    // Content lives as a SIBLING of PillSurface (not inside it): pill content
    // is always smaller than the pill body and centered, so no rounded clipping
    // is needed. Keeping it at the Item-root level avoids interfering with
    // PillSurface's internal holder/clipping machinery.
    Item {
        id: contentArea
        anchors.centerIn: parent
        // Push the content down by half the bleed: the plate is centred on its
        // FULL height, but the top of it is off-screen, so without this the
        // visible content would sit half a bleed too high.
        anchors.verticalCenterOffset: root.contentOffset
        implicitWidth: children[root.primaryContentIndex]?.implicitWidth ?? 0
        implicitHeight: children[root.primaryContentIndex]?.implicitHeight ?? 0
    }

    // Width animation matches Tray.qml for consistent bar visual behavior
    Behavior on implicitWidth {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
    }

    // Validate single-child assumption on component completion
    Component.onCompleted: {
        if (contentArea.children.length === 0) {
            console.warn("PillContainer: No children provided - pill will be invisible");
        } else if (contentArea.children.length > 1) {
            console.warn(`PillContainer: Expected 1 child, got ${contentArea.children.length}. Using first child for width calculation.`);
        }
    }

    // Shared WrappedLoader component for lazy loading pill items.
    // Each loader should have a 'name' property for popout detection.
    component WrappedLoader: Loader {
        required property string name

        Layout.alignment: Qt.AlignVCenter
        asynchronous: true
        visible: active
    }
}
