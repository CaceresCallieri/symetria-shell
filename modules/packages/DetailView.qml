pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Scrollable detail view for a single package.
///
/// Displays comprehensive package info in sections: overview, dependencies,
/// optional deps, required by (installed only), metadata, AUR info, and actions.
/// Uses data from the Packages.selectedDetail model.
StyledFlickable {
    id: root

    required property var detail

    flickableDirection: Flickable.VerticalFlick
    contentHeight: mainColumn.implicitHeight + Appearance.padding.large
    clip: true

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    ColumnLayout {
        id: mainColumn

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ===== Overview Section =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Overview")

            // Full description (wrapped)
            StyledText {
                Layout.fillWidth: true
                text: root.detail?.description ?? ""
                wrapMode: Text.WordWrap
                color: Colours.palette.m3onSurfaceVariant
            }

            // URL (clickable)
            Row {
                visible: (root.detail?.url ?? "") !== ""
                spacing: Appearance.spacing.small

                MaterialIcon {
                    text: "link"
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.detail?.url ?? ""
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3primary
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Packages.openUrl(root.detail.url)
                    }
                }
            }

            // Licenses
            Row {
                visible: (root.detail?.licenses ?? "") !== ""
                spacing: Appearance.spacing.small

                StyledText {
                    text: qsTr("License:")
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3outline
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.detail?.licenses ?? ""
                    font.pointSize: Appearance.font.size.small
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Architecture
            Row {
                visible: (root.detail?.architecture ?? "") !== ""
                spacing: Appearance.spacing.small

                StyledText {
                    text: qsTr("Architecture:")
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3outline
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.detail?.architecture ?? ""
                    font.pointSize: Appearance.font.size.small
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Provides
            Row {
                visible: (root.detail?.provides ?? "None") !== "None"
                spacing: Appearance.spacing.small

                StyledText {
                    text: qsTr("Provides:")
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3outline
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.detail?.provides ?? ""
                    font.pointSize: Appearance.font.size.small
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ===== Dependencies Section =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Dependencies")
            visible: (root.detail?.depsList ?? []).length > 0

            Flow {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                Repeater {
                    model: root.detail?.depsList ?? []

                    DependencyChip {
                        required property string modelData
                        depName: modelData
                    }
                }
            }
        }

        // ===== Optional Dependencies Section =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Optional Dependencies")
            visible: optDepsRepeater.count > 0

            Repeater {
                id: optDepsRepeater
                model: root.detail?.optDepsList ?? []

                RowLayout {
                    id: optDepDelegate

                    required property var modelData

                    readonly property string depName: modelData.name ?? ""
                    readonly property string depDescription: modelData.description ?? ""
                    readonly property bool depInstalled: modelData.installed ?? false

                    Layout.fillWidth: true
                    spacing: Appearance.spacing.small

                    MaterialIcon {
                        text: optDepDelegate.depInstalled ? "check_circle" : "circle"
                        font.pointSize: Appearance.font.size.small
                        color: optDepDelegate.depInstalled ? Colours.palette.m3primary : Colours.palette.m3outline
                        fill: optDepDelegate.depInstalled ? 1 : 0
                    }

                    StyledText {
                        text: optDepDelegate.depName
                        font.pointSize: Appearance.font.size.small
                        font.weight: Font.Medium
                        font.family: "monospace"
                        color: Colours.palette.m3primary

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Packages.searchFromDetail(optDepDelegate.depName)
                        }
                    }

                    StyledText {
                        visible: optDepDelegate.depDescription !== ""
                        text: optDepDelegate.depDescription
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outline
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ===== Make Dependencies Section (AUR only) =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Make Dependencies")
            visible: (root.detail?.isAur ?? false) && (root.detail?.makeDependsList ?? []).length > 0

            Flow {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                Repeater {
                    model: root.detail?.makeDependsList ?? []

                    DependencyChip {
                        required property string modelData
                        depName: modelData
                    }
                }
            }
        }

        // ===== Required By Section (installed only) =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Required By")
            visible: (root.detail?.installed ?? false) && (root.detail?.requiredByList ?? []).length > 0

            Flow {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                Repeater {
                    model: root.detail?.requiredByList ?? []

                    DependencyChip {
                        required property string modelData
                        depName: modelData
                    }
                }
            }
        }

        // ===== Optional For Section (installed only) =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Optional For")
            visible: (root.detail?.installed ?? false) && (root.detail?.optionalForList ?? []).length > 0

            Flow {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                Repeater {
                    model: root.detail?.optionalForList ?? []

                    DependencyChip {
                        required property string modelData
                        depName: modelData
                    }
                }
            }
        }

        // ===== Package Details Section =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("Package Details")

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: metadataColumn.implicitHeight + Appearance.padding.large * 2
                radius: Appearance.rounding.normal
                color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

                ColumnLayout {
                    id: metadataColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Appearance.padding.large
                    spacing: Appearance.spacing.small / 2

                    PropertyRow {
                        label: qsTr("Download Size")
                        value: root.detail?.downloadSize || qsTr("N/A")
                        visible: (root.detail?.downloadSize ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Installed Size")
                        value: root.detail?.installedSize || qsTr("N/A")
                        visible: (root.detail?.installedSize ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Build Date")
                        value: root.detail?.buildDate ?? ""
                        visible: (root.detail?.buildDate ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Packager")
                        value: root.detail?.packager ?? ""
                        visible: (root.detail?.packager ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Install Date")
                        value: root.detail?.installDate ?? ""
                        visible: (root.detail?.installDate ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Install Reason")
                        value: root.detail?.installReason ?? ""
                        visible: (root.detail?.installReason ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Conflicts With")
                        value: root.detail?.conflictsWith ?? ""
                        visible: (root.detail?.conflictsWith ?? "None") !== "None"
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Replaces")
                        value: root.detail?.replaces ?? ""
                        visible: (root.detail?.replaces ?? "None") !== "None"
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Groups")
                        value: root.detail?.groups ?? ""
                        visible: (root.detail?.groups ?? "None") !== "None"
                    }
                }
            }
        }

        // ===== AUR Info Section (AUR only) =====
        DetailSection {
            Layout.fillWidth: true
            title: qsTr("AUR Info")
            visible: root.detail?.isAur ?? false

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: aurColumn.implicitHeight + Appearance.padding.large * 2
                radius: Appearance.rounding.normal
                color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

                ColumnLayout {
                    id: aurColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Appearance.padding.large
                    spacing: Appearance.spacing.small / 2

                    PropertyRow {
                        label: qsTr("Votes")
                        value: (root.detail?.votes ?? -1) >= 0 ? root.detail.votes.toString() : qsTr("N/A")
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Popularity")
                        value: (root.detail?.popularity ?? -1) >= 0 ? root.detail.popularity.toFixed(2) : qsTr("N/A")
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Maintainer")
                        value: root.detail?.maintainer || qsTr("Orphaned")
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("First Submitted")
                        value: root.detail?.firstSubmitted ?? ""
                        visible: (root.detail?.firstSubmitted ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Last Modified")
                        value: root.detail?.lastModified ?? ""
                        visible: (root.detail?.lastModified ?? "") !== ""
                    }

                    PropertyRow {
                        showTopMargin: true
                        label: qsTr("Out of Date")
                        value: root.detail?.outOfDate || qsTr("No")
                        visible: (root.detail?.outOfDate ?? "") !== ""
                    }
                }
            }
        }

        // ===== Action Buttons =====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.large
            spacing: Appearance.spacing.normal

            // Open URL button
            StyledRect {
                visible: (root.detail?.url ?? "") !== ""
                Layout.fillWidth: true
                implicitHeight: urlRow.implicitHeight + Appearance.padding.normal * 2
                radius: Appearance.rounding.normal
                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                StateLayer {
                    radius: parent.radius

                    function onClicked(): void {
                        Packages.openUrl(root.detail?.url ?? "");
                    }
                }

                Row {
                    id: urlRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.small

                    MaterialIcon {
                        text: "open_in_new"
                        color: Colours.palette.m3onSurface
                        font.pointSize: Appearance.font.size.normal
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: qsTr("Open URL")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Appearance.font.size.normal
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Copy install command button
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: copyRow.implicitHeight + Appearance.padding.normal * 2
                radius: Appearance.rounding.normal
                color: Colours.palette.m3primaryContainer

                StateLayer {
                    radius: parent.radius
                    color: Colours.palette.m3onPrimaryContainer

                    function onClicked(): void {
                        Packages.copyInstallCommand(root.detail?.name ?? "");
                    }
                }

                Row {
                    id: copyRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.small

                    MaterialIcon {
                        text: "content_copy"
                        color: Colours.palette.m3onPrimaryContainer
                        font.pointSize: Appearance.font.size.normal
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: qsTr("Copy install command")
                        color: Colours.palette.m3onPrimaryContainer
                        font.pointSize: Appearance.font.size.normal
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
