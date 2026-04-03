pragma ComponentBehavior: Bound

import qs.config
import QtQuick

/// Reusable fade-in/fade-out container.
///
/// Encapsulates the common pattern of:
///   visible: condition
///   opacity: condition ? 1 : 0
///   Behavior on opacity { Anim {} }
///
/// Children are added directly to this Item. Implicit size is
/// forwarded from the first child, making it work naturally with
/// Layout.* properties in parent containers.
///
/// Usage:
///   FadeTransition {
///       show: someCondition
///       YourContent { ... }
///   }
Item {
    id: root

    /// Controls visibility with animated opacity fade
    property bool show: false

    // Forward implicit size from first child for proper layout integration
    implicitWidth: children.length > 0 ? children[0].implicitWidth : 0
    implicitHeight: children.length > 0 ? children[0].implicitHeight : 0

    visible: show
    opacity: show ? 1 : 0

    Behavior on opacity {
        Anim {}
    }
}
