pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick

/// Detail header for the packages drawer.
/// Shows the back button, package name/version, repo badge, and installed indicator.
/// Uses the Packages singleton directly for selectedDetail data.
Item {
    id: root

    signal backRequested()

    implicitHeight: detailHeaderRow.implicitHeight

    Row {
        id: detailHeaderRow

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.normal

        // Back button
        StyledRect {
            id: backButton

            implicitWidth: backIcon.implicitWidth + Appearance.padding.normal * 2
            implicitHeight: backIcon.implicitHeight + Appearance.padding.normal * 2
            radius: Appearance.rounding.full
            color: "transparent"
            anchors.verticalCenter: parent.verticalCenter

            MaterialIcon {
                id: backIcon
                anchors.centerIn: parent
                text: "arrow_back"
                color: Colours.palette.m3onSurface
            }

            StateLayer {
                radius: parent.radius

                function onClicked(): void {
                    root.backRequested();
                }
            }
        }

        // Package name + version
        Column {
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: Appearance.spacing.small

                StyledText {
                    text: Packages.selectedDetail?.name ?? ""
                    font.pointSize: Appearance.font.size.larger
                    font.weight: Font.Medium
                }

                StyledText {
                    text: Packages.selectedDetail?.version ?? ""
                    font.pointSize: Appearance.font.size.normal
                    color: Colours.palette.m3outline
                    anchors.baseline: parent.children[0]?.baseline
                }
            }

            Row {
                spacing: Appearance.spacing.small

                // Repo badge
                StyledRect {
                    visible: (Packages.selectedDetail?.repo ?? "") !== ""
                    color: {
                        const d = Packages.selectedDetail;
                        if (!d) return "transparent";
                        if (d.installed) return Qt.alpha(Colours.palette.m3primary, 0.15);
                        if (d.isAur) return Qt.alpha(Colours.palette.m3tertiary, 0.15);
                        return Colours.palette.m3surfaceContainerHighest;
                    }
                    radius: Appearance.rounding.full
                    implicitWidth: repoText.implicitWidth + Appearance.padding.normal * 2
                    implicitHeight: repoText.implicitHeight + Appearance.padding.small * 2

                    StyledText {
                        id: repoText
                        anchors.centerIn: parent
                        text: Packages.selectedDetail?.repo ?? ""
                        font.pointSize: Appearance.font.size.small
                        font.weight: Font.Medium
                        color: {
                            const d = Packages.selectedDetail;
                            if (!d) return Colours.palette.m3onSurfaceVariant;
                            if (d.installed) return Colours.palette.m3primary;
                            if (d.isAur) return Colours.palette.m3tertiary;
                            return Colours.palette.m3onSurfaceVariant;
                        }
                    }
                }

                // Installed indicator
                Row {
                    visible: Packages.selectedDetail?.installed ?? false
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter

                    MaterialIcon {
                        text: "check_circle"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: qsTr("Installed")
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
