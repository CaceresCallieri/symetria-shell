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

    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: contentSize
    Layout.leftMargin: isActive ? activePadding + activeMargin : 0
    Layout.rightMargin: isActive ? activePadding + activeMargin : 0

    spacing: 0

    StyledText {
        id: indicator

        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
        Layout.preferredWidth: Config.bar.sizes.innerWidth - Appearance.padding.small * 2

        animate: true
        text: {
            const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
            if (ws) {
                const customIcon = Icons.getNamedWsIcon(ws.name);
                if (customIcon) return customIcon;
                // For named workspaces (negative IDs), show first letter of name as fallback
                if (root.ws < 0 && ws.name) return ws.name[0].toUpperCase();
            }
            return Icons.romanize(root.ws);
        }
        color: {
            if (root.isActive)
                return Colours.palette.m3onPrimary;
            if (Config.bar.workspaces.occupiedBg || root.isOccupied)
                return Colours.palette.m3onSurface;
            return Colours.layer(Colours.palette.m3outlineVariant, 2);
        }
        horizontalAlignment: Qt.AlignHCenter
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
