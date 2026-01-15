// Note: No pragma ComponentBehavior: Bound here - allows WrappedLoader
// to be used by child components via PillContainer.WrappedLoader

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Base component for glassmorphism pill containers in the bar.
// Provides consistent styling and layout structure for StatusIcons, TimePill, SystemPill, etc.
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

StyledRect {
    id: root

    // Content color passed to child components (default: m3tertiary for info pills).
    // StatusIcons uses m3secondary for visual distinction between status and info pills.
    property color colour: Colours.palette.m3tertiary

    // Popout interface: reference to the child's content container for Bar.qml's
    // detectChildPopout() integration. Uses 'property Item' instead of alias to:
    // 1. Allow null default (children without popouts can leave unset)
    // 2. Avoid parse errors when child ID doesn't exist at declaration time
    // Children with popouts should set: iconContainer: <RowLayout id>
    property Item iconContainer: null

    // Glassmorphism styling (subtle intensity for background containers).
    // Centralized here - changes apply to all pills automatically.
    readonly property var glassStyle: Colours.glassmorphism(
        Colours.palette.m3surfaceContainerHigh,
        Colours.glass.subtle
    )

    color: glassStyle.background
    radius: Appearance.rounding.full
    border.width: 1
    border.color: glassStyle.border

    // Internal padding constant for pill edges
    readonly property int pillPadding: Appearance.spacing.large

    // Index of primary content child (assumes single RowLayout child)
    readonly property int primaryContentIndex: 0

    clip: true
    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: contentArea.children[primaryContentIndex]?.implicitWidth ?? 0

    // Default property: children declared inside PillContainer { ... } are automatically
    // reparented to contentArea via QML's default property mechanism.
    // This enables natural syntax: PillContainer { RowLayout { ... } }
    default property alias content: contentArea.data

    Item {
        id: contentArea
        anchors.centerIn: parent
        implicitWidth: children[root.primaryContentIndex]?.implicitWidth ?? 0
        implicitHeight: children[root.primaryContentIndex]?.implicitHeight ?? 0
    }

    Behavior on implicitWidth {
        Anim {}
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
