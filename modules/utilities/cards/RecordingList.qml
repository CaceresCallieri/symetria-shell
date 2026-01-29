pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel

ColumnLayout {
    id: root

    required property var props
    required property var visibilities

    spacing: 0

    WrapperMouseArea {
        Layout.fillWidth: true

        cursorShape: Qt.PointingHandCursor
        onClicked: root.props.recordingListExpanded = !root.props.recordingListExpanded

        RowLayout {
            spacing: Appearance.spacing.smaller

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "list"
                font.pointSize: Appearance.font.size.large
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: qsTr("Recordings")
                font.pointSize: Appearance.font.size.normal
            }

            IconButton {
                icon: root.props.recordingListExpanded ? "unfold_less" : "unfold_more"
                type: IconButton.Text
                label.animate: true
                onClicked: root.props.recordingListExpanded = !root.props.recordingListExpanded
            }
        }
    }

    StyledListView {
        id: list

        model: FolderListModel {
            id: recordingsModel
            folder: "file://" + Paths.recsdir
            nameFilters: ["recording_*.mp4"]
            showDirs: false
            showDotAndDotDot: false
            sortField: FolderListModel.Time
            sortReversed: false  // Time sort: false = descending (newest first)
        }

        // Force refresh when recording stops to ensure new file is detected
        // We poll because the CLI moves the file asynchronously after the recorder process dies
        Timer {
            id: refreshTimer
            interval: 500  // Poll every 500ms
            repeat: true
            property int expectedCount: 0
            property int attempts: 0

            onTriggered: {
                attempts++;
                // Force model refresh by toggling folder
                const originalFolder = recordingsModel.folder;
                recordingsModel.folder = "";
                recordingsModel.folder = originalFolder;

                if (recordingsModel.count >= expectedCount) {
                    stop();
                    attempts = 0;
                } else if (attempts >= 10) {
                    // Timeout after 5 seconds (10 * 500ms)
                    console.warn("RecordingList: timeout waiting for new recording");
                    stop();
                    attempts = 0;
                }
            }
        }

        Connections {
            target: Recorder
            function onRunningChanged(): void {
                if (!Recorder.running) {
                    // Stop any existing polling before starting new one
                    if (refreshTimer.running)
                        refreshTimer.stop();
                    refreshTimer.attempts = 0;
                    refreshTimer.expectedCount = recordingsModel.count + 1;
                    refreshTimer.start();
                }
            }
        }

        Layout.fillWidth: true
        Layout.rightMargin: -Appearance.spacing.small
        implicitHeight: (Appearance.font.size.larger + Appearance.padding.small) * (root.props.recordingListExpanded ? 10 : 3)
        clip: true

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        delegate: RowLayout {
            id: recording

            // FolderListModel provides these role properties directly
            required property string fileBaseName
            required property string filePath

            anchors.left: list.contentItem.left
            anchors.right: list.contentItem.right
            anchors.rightMargin: Appearance.spacing.small
            spacing: Appearance.spacing.small / 2

            StyledText {
                Layout.fillWidth: true
                Layout.rightMargin: Appearance.spacing.small / 2
                text: {
                    const time = recording.fileBaseName;
                    const matches = time.match(/^recording_(\d{4})(\d{2})(\d{2})_(\d{2})-(\d{2})-(\d{2})/);
                    if (!matches)
                        return qsTr("Recording (%1)").arg(time.replace("recording_", ""));

                    const [, year, month, day, hour, minute, second] = matches;
                    // Validate date component ranges
                    if (+month < 1 || +month > 12 || +day < 1 || +day > 31 ||
                        +hour > 23 || +minute > 59 || +second > 59) {
                        console.warn("RecordingList: invalid date in filename:", time);
                        return time;
                    }

                    const date = new Date(+year, +month - 1, +day, +hour, +minute, +second);
                    // Check if the date overflowed (JS Date auto-corrects invalid dates)
                    if (date.getMonth() !== +month - 1 || date.getDate() !== +day) {
                        console.warn("RecordingList: date overflow in filename:", time);
                        return qsTr("Recording (%1)").arg(time.replace("recording_", ""));
                    }
                    return qsTr("Recording at %1").arg(Qt.formatDateTime(date, "d/M/yy HH:mm"));
                }
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            IconButton {
                icon: "play_arrow"
                type: IconButton.Text
                onClicked: {
                    root.visibilities.utilities = false;
                    root.visibilities.sidebar = false;
                    Quickshell.execDetached(["app2unit", "--", ...Config.general.apps.playback, recording.filePath]);
                }
            }

            IconButton {
                icon: "folder"
                type: IconButton.Text
                onClicked: {
                    root.visibilities.utilities = false;
                    root.visibilities.sidebar = false;
                    Quickshell.execDetached(["app2unit", "--", ...Config.general.apps.explorer, recording.filePath]);
                }
            }

            IconButton {
                icon: "delete_forever"
                type: IconButton.Text
                label.color: Colours.palette.m3error
                stateLayer.color: Colours.palette.m3error
                onClicked: root.props.recordingConfirmDelete = recording.filePath
            }
        }

        add: Transition {
            Anim {
                property: "opacity"
                from: 0
                to: 1
            }
            Anim {
                property: "scale"
                from: 0.5
                to: 1
            }
        }

        remove: Transition {
            Anim {
                property: "opacity"
                to: 0
            }
            Anim {
                property: "scale"
                to: 0.5
            }
        }

        displaced: Transition {
            Anim {
                properties: "opacity,scale"
                to: 1
            }
            Anim {
                property: "y"
            }
        }

        Loader {
            anchors.centerIn: parent

            opacity: list.count === 0 ? 1 : 0
            active: opacity > 0
            asynchronous: true

            sourceComponent: ColumnLayout {
                spacing: Appearance.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "scan_delete"
                    color: Colours.palette.m3outline
                    font.pointSize: Appearance.font.size.extraLarge

                    opacity: root.props.recordingListExpanded ? 1 : 0
                    scale: root.props.recordingListExpanded ? 1 : 0
                    Layout.preferredHeight: root.props.recordingListExpanded ? implicitHeight : 0

                    Behavior on opacity {
                        Anim {}
                    }

                    Behavior on scale {
                        Anim {}
                    }

                    Behavior on Layout.preferredHeight {
                        Anim {}
                    }
                }

                RowLayout {
                    spacing: Appearance.spacing.smaller

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "scan_delete"
                        color: Colours.palette.m3outline

                        opacity: !root.props.recordingListExpanded ? 1 : 0
                        scale: !root.props.recordingListExpanded ? 1 : 0
                        Layout.preferredWidth: !root.props.recordingListExpanded ? implicitWidth : 0

                        Behavior on opacity {
                            Anim {}
                        }

                        Behavior on scale {
                            Anim {}
                        }

                        Behavior on Layout.preferredWidth {
                            Anim {}
                        }
                    }

                    StyledText {
                        text: qsTr("No recordings found")
                        color: Colours.palette.m3outline
                    }
                }
            }

            Behavior on opacity {
                Anim {}
            }
        }

        Behavior on implicitHeight {
            Anim {
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        }
    }
}
