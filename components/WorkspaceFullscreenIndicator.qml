import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Animated fullscreen/maximize badge for a workspace. Shows a Material icon
/// when the workspace contains a window in maximize mode (`fullscreen === 1`)
/// AND the workspace is currently active. True fullscreen (mode 2) is excluded
/// because those windows typically hide the bar entirely.
///
/// Used by the top-bar Workspace.qml. It was extracted to keep this consistent
/// with the merged agentbar's own workspace pill, which went out with Symmetria
/// IDE; the one consumer left keeps it here rather than inlining it back.
MaterialIcon {
    id: root

    required property int wsId
    required property bool isActive

    // Detect maximize mode (fullscreen === 1) on this workspace by scanning toplevels.
    // Uses Hypr.workspaceById() so the binding tracks workspace identity changes.
    readonly property bool hasMaximized: {
        const ws = Hypr.workspaceById(root.wsId);
        if (!ws?.toplevels?.values)
            return false;

        for (const toplevel of ws.toplevels.values) {
            if (toplevel?.lastIpcObject?.fullscreen === 1)
                return true;
        }
        return false;
    }

    // Combined condition: visually appears only on the active workspace.
    readonly property bool shouldShow: hasMaximized && isActive

    Layout.alignment: Qt.AlignVCenter
    Layout.leftMargin: shouldShow ? Appearance.spacing.small : 0

    // Only allocate layout space when needed (collapsed when no maximized window).
    visible: hasMaximized
    scale: shouldShow ? 1 : 0
    opacity: shouldShow ? 1 : 0

    text: "fullscreen"
    color: Colours.palette.m3onSurface
    font.pointSize: Appearance.font.size.small

    Behavior on opacity {
        Anim {}
    }
    Behavior on scale {
        Anim {}
    }
    Behavior on Layout.leftMargin {
        Anim {}
    }
}
