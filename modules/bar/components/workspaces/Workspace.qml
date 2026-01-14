import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    required property int wsId
    required property int activeWsId
    required property var occupied

    readonly property bool isWorkspace: true // Flag for finding workspace children
    readonly property bool isActive: activeWsId === ws
    // Padding = space inside the selector pill (both sides)
    readonly property int activePadding: Appearance.padding.large
    // Margin = configurable gap outside the selector pill (both sides)
    // Set to 0 for no gap, or use Appearance.padding.* values for visible separation
    readonly property int activeMargin: 0
    // Content size: actual visual width of workspace content (indicator text + window icons)
    readonly property int contentSize: implicitWidth + (hasWindows ? Appearance.padding.small : 0)
    // Indicator offset: how far left the indicator extends from workspace.x
    // Used by ActiveIndicator to position itself correctly
    readonly property int indicatorOffset: isActive ? activePadding : 0
    // Indicator size: total width the indicator pill should be
    // Used by ActiveIndicator to set its width
    readonly property int indicatorSize: contentSize + (isActive ? activePadding * 2 : 0)

    readonly property int ws: wsId
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows && isActive

    // Cached workspace reference to avoid repeated find() lookups
    readonly property var currentWorkspace: Hypr.workspaces.values.find(w => w.id === root.ws) ?? null

    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: contentSize
    Layout.leftMargin: isActive ? activePadding + activeMargin : 0
    Layout.rightMargin: isActive ? activePadding + activeMargin : 0

    spacing: 0

    // Workspace indicator: roman numeral, letter, or icon
    // Uses Loader to render MaterialIcon for named icons (e.g., "mat:sports_esports")
    // or StyledText for single characters and roman numerals
    Loader {
        id: indicator

        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
        Layout.preferredWidth: Config.bar.sizes.indicatorHeight

        // Raw icon value from config or fallback
        readonly property string rawIcon: {
            if (root.currentWorkspace) {
                const customIcon = Icons.getNamedWsIcon(root.currentWorkspace.name);
                // Validate icon is not empty or just the prefix
                if (customIcon && customIcon !== Icons.materialIconPrefix) return customIcon;
                // For named workspaces (negative IDs), show first letter of name as fallback
                if (root.ws < 0 && root.currentWorkspace.name) return root.currentWorkspace.name[0].toUpperCase();
            }
            return Icons.romanize(root.ws);
        }

        // Parse icon using centralized helper (handles prefix stripping and validation)
        readonly property var parsedIcon: Icons.parseIcon(rawIcon)
        readonly property bool useMaterialIcon: parsedIcon.useMaterial
        readonly property string iconText: parsedIcon.iconText

        readonly property color indicatorColor: {
            if (root.isActive)
                return Colours.palette.m3onSurface;
            if (Config.bar.workspaces.occupiedBg || root.isOccupied)
                return Colours.palette.m3onSurface;
            return Colours.layer(Colours.palette.m3outlineVariant, 2);
        }

        sourceComponent: useMaterialIcon ? materialIconComp : styledTextComp

        Component {
            id: materialIconComp

            MaterialIcon {
                fill: 1
                text: indicator.iconText
                color: indicator.indicatorColor
                horizontalAlignment: Qt.AlignHCenter
            }
        }

        Component {
            id: styledTextComp

            StyledText {
                animate: true
                text: indicator.iconText
                color: indicator.indicatorColor
                horizontalAlignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        id: windows

        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: true
        Layout.leftMargin: -Config.bar.sizes.innerWidth / 10

        visible: active
        active: root.hasWindows
        asynchronous: true

        sourceComponent: WorkspaceAppIcons {
            workspaceId: root.ws
        }
    }

    // Fullscreen/Maximize indicator - shows at end of active workspace
    MaterialIcon {
        id: fullscreenIndicator

        // Detect maximize mode (fullscreen 1) on this workspace
        // Note: Intentionally excludes true fullscreen (mode 2) as those typically hide the bar
        readonly property bool hasMaximized: {
            // Use cached workspace with explicit null safety
            if (!root.currentWorkspace?.toplevels?.values) return false;

            // Manual iteration for better reactivity and null safety
            for (const toplevel of root.currentWorkspace.toplevels.values) {
                if (toplevel?.lastIpcObject?.fullscreen === 1) {
                    return true;
                }
            }
            return false;
        }

        // Combined condition for cleaner bindings
        readonly property bool shouldShow: hasMaximized && root.isActive

        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: shouldShow ? Appearance.spacing.small : 0

        visible: hasMaximized  // Only allocate layout space when needed
        scale: shouldShow ? 1 : 0
        opacity: shouldShow ? 1 : 0

        text: "fullscreen"
        color: Colours.palette.m3onSurface
        font.pointSize: Appearance.font.size.small

        Behavior on opacity { Anim {} }
        Behavior on scale { Anim {} }
        Behavior on Layout.leftMargin { Anim {} }
    }

    Behavior on Layout.preferredWidth {
        Anim {}
    }

    Behavior on Layout.leftMargin {
        Anim {}
    }

    Behavior on Layout.rightMargin {
        Anim {}
    }
}
