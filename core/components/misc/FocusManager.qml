import QtQuick

/// Manages focus for drawer panels that need keyboard input.
///
/// This component encapsulates the standard pattern for focus management:
/// 1. Focuses the target when the bound visibility becomes true
/// 2. Guards against focus-stealing during Loader pre-loading
/// 3. Provides optional callbacks for open/close events
///
/// Usage:
/// ```qml
/// FocusManager {
///     active: root.visibilities.launcher
///     target: searchField
///     onClose: () => searchField.text = ""
/// }
/// ```
QtObject {
    id: root

    /// Whether the managed component is active/visible.
    /// Bind this to the drawer's visibility property.
    required property bool active

    /// The Item to focus when active becomes true.
    /// Must have forceActiveFocus() method (all Items do).
    required property Item target

    /// Optional callback invoked when active changes to true.
    /// Called after focus is set.
    property var onOpen: null

    /// Optional callback invoked when active changes to false.
    /// Use for cleanup like clearing text fields.
    property var onClose: null

    onActiveChanged: {
        if (active) {
            target.forceActiveFocus();
            if (onOpen)
                onOpen();
        } else {
            if (onClose)
                onClose();
        }
    }

    Component.onCompleted: {
        // Guard: component may be pre-loaded by Loader while drawer is hidden.
        // Only focus if already active to prevent stealing focus.
        if (active)
            target.forceActiveFocus();
    }
}
