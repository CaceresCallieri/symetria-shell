pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Delegate for a single package search result.
///
/// Shows repo badge, package name + version, description, and installed indicator.
/// Clicking copies `paru -S <name>` to clipboard.
Item {
    id: root

    required property var modelData

    // Null-safe access to entry fields
    readonly property string repo: modelData?.repo ?? ""
    readonly property string packageName: modelData?.name ?? ""
    readonly property string version: modelData?.version ?? ""
    readonly property string description: modelData?.description ?? ""
    readonly property bool installed: modelData?.installed ?? false
    readonly property bool isAur: modelData?.isAur ?? false
    readonly property int votes: modelData?.votes ?? -1

    implicitHeight: Config.packages.sizes.itemHeight

    // ListView reuseItems causes parent to be null during delegate recycling
    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Appearance.rounding.normal

        function onClicked(): void {
            Packages.copyInstallCommand(root.packageName);
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Appearance.padding.larger
        anchors.rightMargin: Appearance.padding.larger
        anchors.topMargin: Appearance.padding.smaller
        anchors.bottomMargin: Appearance.padding.smaller

        // Repo badge (small colored pill)
        StyledRect {
            id: repoBadge

            anchors.verticalCenter: parent.verticalCenter

            color: root.installed
                ? Qt.alpha(Colours.palette.m3primary, 0.15)
                : root.isAur
                    ? Qt.alpha(Colours.palette.m3tertiary, 0.15)
                    : Colours.palette.m3surfaceContainerHighest
            radius: Appearance.rounding.full

            implicitWidth: repoLabel.implicitWidth + Appearance.padding.normal * 2
            implicitHeight: repoLabel.implicitHeight + Appearance.padding.small * 2

            StyledText {
                id: repoLabel

                anchors.centerIn: parent

                text: root.repo
                font.pointSize: Appearance.font.size.small
                font.weight: Font.Medium
                color: root.installed
                    ? Colours.palette.m3primary
                    : root.isAur
                        ? Colours.palette.m3tertiary
                        : Colours.palette.m3onSurfaceVariant
            }
        }

        // Name + version + description column
        Item {
            anchors.left: repoBadge.right
            anchors.right: root.isAur ? votesBadge.left : installedIcon.left
            anchors.leftMargin: Appearance.spacing.normal
            anchors.rightMargin: Appearance.spacing.small
            anchors.verticalCenter: parent.verticalCenter

            implicitHeight: nameRow.implicitHeight + descText.implicitHeight

            // Name and version on top line
            Row {
                id: nameRow

                spacing: Appearance.spacing.small

                StyledText {
                    id: packageNameText

                    text: root.packageName
                    font.pointSize: Appearance.font.size.normal
                    font.weight: Font.Medium
                }

                StyledText {
                    text: root.version
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3outline
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    anchors.verticalCenter: packageNameText.verticalCenter
                }
            }

            // Description below
            StyledText {
                id: descText

                anchors.top: nameRow.bottom
                width: parent.width

                text: root.description
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        // Votes badge (AUR only)
        Row {
            id: votesBadge

            visible: root.isAur && root.votes >= 0
            spacing: 2

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: installedIcon.left
            anchors.rightMargin: installedIcon.visible ? Appearance.spacing.small : 0

            MaterialIcon {
                text: "thumb_up"
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3tertiary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.votes.toString()
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3tertiary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Installed checkmark
        MaterialIcon {
            id: installedIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right

            visible: root.installed
            text: "check_circle"
            color: Colours.palette.m3primary
            font.pointSize: Appearance.font.size.large
        }
    }
}
