pragma ComponentBehavior: Bound

import qs.components
import qs.components.images
import qs.components.filedialog
import qs.services
import qs.config
import qs.utils
import Quickshell
import Quickshell.Hyprland
import QtQuick

Item {
    id: root

    // Screen property for per-monitor workspace tracking
    required property ShellScreen screen

    // Workspace tracking - direct lookup like bar/Workspaces.qml pattern
    readonly property int workspaceId: Hypr.monitorFor(screen).activeWorkspace?.id ?? 1
    readonly property string workspaceName: Hypr.monitorFor(screen).activeWorkspace?.name ?? ""

    // Fix 2: Readiness checks to prevent race condition during initialization
    readonly property bool workspaceDataReady: Hypr.monitorFor(screen).activeWorkspace !== null
    readonly property bool mapReady: Wallpapers.workspaceMapVersion > 0 || !Config.background.perWorkspaceWallpapers.enabled

    // Source depends on per-workspace setting
    property string source: {
        // Force re-evaluation when map updates by referencing version
        const _ = Wallpapers.workspaceMapVersion;

        // Focus mode: release texture once the wrapper fade-out completes.
        // wallpaperLoaded flips false after Wallpapers' unload timer fires.
        if (!Wallpapers.wallpaperLoaded)
            return "";

        // Safe fallback during initialization
        if (Config.background.perWorkspaceWallpapers.enabled && (!workspaceDataReady || !mapReady))
            return Wallpapers.actualCurrent;

        if (Wallpapers.showPreview)
            return Wallpapers.previewPath;
        if (Config.background.perWorkspaceWallpapers.enabled)
            return Wallpapers.getWallpaperForWorkspace(workspaceId, workspaceName);
        return Wallpapers.actualCurrent;
    }

    property Image current: one

    anchors.fill: parent

    onSourceChanged: {
        if (!source) {
            // Drop GPU textures. Setting `path` alone updates CachingImageManager's
            // m_path but never clears the Image's `source` property — the texture
            // would stay resident. Clear `source` directly on both Imgs so Qt
            // releases the decoded pixmap and GPU texture.
            current = null;
            one.path = "";
            one.source = "";
            two.path = "";
            two.source = "";
        } else if (current === one)
            two.update();
        else
            one.update();
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => one.update());
    }

    Loader {
        anchors.fill: parent

        // Skip the fallback UI during focus mode — `source` is intentionally
        // empty there, not because the wallpaper is missing.
        active: !root.source && Wallpapers.wallpaperLoaded
        asynchronous: true

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Appearance.spacing.large

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.extraLarge * 5
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Appearance.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.extraLarge * 2
                        font.bold: true
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Appearance.padding.large * 2
                        implicitHeight: selectWallText.implicitHeight + Appearance.padding.small * 2

                        radius: Appearance.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary

                            function onClicked(): void {
                                dialog.open();
                            }
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font.pointSize: Appearance.font.size.large
                        }
                    }
                }
            }
        }
    }

    Img {
        id: one
    }

    Img {
        id: two
    }

    component Img: CachingImage {
        id: img

        function update(): void {
            if (path === root.source)
                root.current = this;
            else
                path = root.source;
        }

        anchors.fill: parent

        opacity: 0
        scale: Wallpapers.showPreview ? 1 : 0.8

        onStatusChanged: {
            if (status === Image.Ready)
                root.current = this;
        }

        states: State {
            name: "visible"
            when: root.current === img

            PropertyChanges {
                img.opacity: 1
                img.scale: 1
            }
        }

        transitions: Transition {
            Anim {
                target: img
                properties: "opacity,scale"
            }
        }
    }
}
