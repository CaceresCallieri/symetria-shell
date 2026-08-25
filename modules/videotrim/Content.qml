pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtMultimedia

/// Quick-trim scrubber for the video-trimmer drawer.
///
/// Loads VideoTrimService.source into a MediaPlayer/VideoOutput, shows a
/// filmstrip timeline (real frames extracted by VideoTrimService) with
/// draggable in/out handles, and hands the chosen [in, out] range to
/// VideoTrimService.trim() for a stream-copy ffmpeg cut.
///
/// The video pane is a FIXED size (not aspect-driven) so implicitHeight is
/// stable the instant the component is created — DrawerVertical reads
/// contentHeight in onCompleted, before any video metadata arrives, so a
/// metadata-driven height would resize the drawer mid-open. Letterboxing via
/// VideoOutput.PreserveAspectFit absorbs the real aspect ratio instead.
Item {
    id: root

    // ── Trim state (seconds) ───────────────────────────────────────
    readonly property real durationSec: player.duration > 0 ? player.duration / 1000 : 0
    property real inPoint: 0
    property real outPoint: 0
    // Minimum kept span — keeps the handles from crossing / producing a 0s clip.
    readonly property real minGap: 0.5

    readonly property real videoW: 560
    readonly property real videoH: 315
    // Number of filmstrip frames to extract across the clip.
    readonly property int thumbCount: 12

    // True once the MediaPlayer has been "primed" (briefly played + paused) so
    // the FFmpeg backend has decoded and latched a frame onto the VideoOutput —
    // without this the pane stays black until the first manual play. Audio is
    // muted until primed so the priming play() makes no sound.
    property bool primed: false

    // Source whose selection + filmstrip have already been initialised, so a
    // duration re-emit doesn't wipe the user's handle drags or re-extract.
    property string preparedSource: ""

    function fmt(sec: real): string {
        if (!isFinite(sec) || sec < 0)
            sec = 0;
        const s = Math.floor(sec % 60);
        const m = Math.floor(sec / 60);
        return `${m}:${s < 10 ? "0" + s : s}`;
    }

    // Map a time (s) to an x within a track of `w` px wide.
    function timeToX(sec: real, w: real): real {
        return durationSec > 0 ? w * (sec / durationSec) : 0;
    }

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight + Appearance.padding.large

    MediaPlayer {
        id: player

        source: VideoTrimService.sourceUrl
        videoOutput: videoOut
        audioOutput: AudioOutput {
            id: audioOut
            muted: !root.primed
        }

        // Reset the selection to the full clip and kick off filmstrip
        // extraction whenever a new source's duration resolves.
        onDurationChanged: {
            const d = player.duration;
            // Initialise selection + filmstrip once per source. Guarding on the
            // source identity prevents a duration re-emit (metadata refresh, or
            // a 0→N→0→N sequence) from discarding the user's handle drags and
            // needlessly re-running extraction.
            if (d > 0 && VideoTrimService.source !== root.preparedSource) {
                root.preparedSource = VideoTrimService.source;
                root.inPoint = 0;
                root.outPoint = d / 1000;
                player.position = 0;
                VideoTrimService.generateThumbnails(d / 1000, root.thumbCount);
            }
        }

        // Prime once the media is loaded/buffered: play briefly (muted) so a
        // frame is decoded onto the output, then primeTimer pauses and parks
        // the head at the start. Without this the pane stays black until the
        // first manual play.
        onMediaStatusChanged: {
            if (!root.primed && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)) {
                play();
                primeTimer.start();
            }
        }

        onPositionChanged: {
            // Event-driven prime completion: the first painted frame advances
            // position past 0, which signals a frame has decoded onto the
            // VideoOutput — more reliable than the fixed primeTimer fallback.
            if (!root.primed && playbackState === MediaPlayer.PlayingState && player.position > 0) {
                root.finishPriming();
                return;
            }
            // Preview-within-selection: stop at the out-point so play() auditions
            // only the kept region rather than running to the end of the source.
            if (root.primed && playbackState === MediaPlayer.PlayingState && player.position >= root.outPoint * 1000)
                pause();
        }
    }

    // Fallback prime completion. HACK: 120 ms is empirical — Qt Multimedia has
    // no "first frame painted" signal, so if position never ticks during the
    // brief priming play() (some backends), this timer forces completion so the
    // pane never stays black. Remove the timer if such a signal becomes
    // available; the onPositionChanged path above is the primary mechanism.
    Timer {
        id: primeTimer
        interval: 120
        onTriggered: root.finishPriming()
    }

    // When the service swaps to a different clip while this Content instance
    // stays alive (panel already open on this monitor), re-arm priming and the
    // per-source init so the new clip shows its poster frame and re-derives its
    // selection rather than inheriting the previous clip's primed state.
    Connections {
        target: VideoTrimService
        function onSourceChanged(): void {
            root.primed = false;
            root.preparedSource = "";
        }
    }

    Item {
        id: container

        anchors.top: parent.top
        anchors.topMargin: Appearance.padding.large
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: content.implicitWidth + Appearance.padding.large * 2
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        PillCard {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Appearance.spacing.normal

            // ── Title row (close at top-right) ─────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: "content_cut"
                    color: Colours.palette.m3primary
                    font.pointSize: Appearance.font.size.large
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Trim — %1").arg(VideoTrimService.sourceName)
                    font.pointSize: Appearance.font.size.normal
                    elide: Text.ElideMiddle
                }

                // Close — a red dot with the shell's raised-claymorphism
                // treatment (no glyph, even on hover) so it reads as part of
                // the system rather than a flat macOS sticker. The StateLayer
                // gives hover/press feedback; PillToggleSurface adds the depth.
                PillToggleSurface {
                    id: macClose

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 20
                    implicitHeight: 20
                    raised: true
                    active: false
                    radius: width / 2
                    inactiveColor: Qt.rgba(0.83, 0.31, 0.29, 1.0)

                    StateLayer {
                        radius: macClose.radius

                        function onClicked(): void {
                            VideoTrimService.close();
                        }
                    }
                }
            }

            // ── Video preview pane ─────────────────────────────────
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: root.videoW
                implicitHeight: root.videoH
                radius: Appearance.rounding.small
                color: "black"
                clip: true

                VideoOutput {
                    id: videoOut
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                // Big centred play/pause affordance over the frame.
                IconButton {
                    anchors.centerIn: parent
                    icon: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                    type: IconButton.Filled
                    toggle: false
                    onClicked: root.togglePlay()
                }
            }

            // ── Transport row: position · selection · duration ─────
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                StyledText {
                    text: root.fmt(player.position / 1000)
                    font.family: Appearance.font.family.mono
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: qsTr("in %1  ·  out %2").arg(root.fmt(root.inPoint)).arg(root.fmt(root.outPoint))
                    font.family: Appearance.font.family.mono
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3primary
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: root.fmt(root.durationSec)
                    font.family: Appearance.font.family.mono
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // ── Filmstrip timeline with in/out handles ─────────────
            Item {
                id: tl

                Layout.fillWidth: true
                Layout.preferredWidth: root.videoW
                implicitHeight: 56

                // Filmstrip background — real frames extracted from the clip.
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: Colours.palette.m3surfaceContainerHighest
                    clip: true

                    Row {
                        anchors.fill: parent

                        Repeater {
                            id: strip
                            model: root.thumbCount

                            delegate: Image {
                                required property int index

                                width: tl.width / root.thumbCount
                                height: tl.height
                                fillMode: Image.PreserveAspectCrop
                                clip: true
                                asynchronous: true
                                cache: false

                                // Deterministic path + version cache-bust. When the
                                // service finishes a batch it bumps thumbnailVersion,
                                // changing the query so Qt reloads (the query is
                                // dropped by toLocalFile(), so the file still
                                // resolves). Chosen over FolderListModel, which did
                                // not reliably surface the externally-written,
                                // mid-session-regenerated frames. A frame that
                                // doesn't exist yet simply renders nothing until the
                                // next version bump.
                                //
                                // The version guard is not cosmetic: these delegates
                                // are built before ffmpeg has written anything, and
                                // version 0 means "no batch has landed yet". Without
                                // it, every open logged one "Cannot open" warning per
                                // frame (12) for files that are merely not extracted
                                // YET — burying real image failures.
                                source: VideoTrimService.thumbnailVersion > 0 ? `file://${VideoTrimService.thumbnailDir}/thumb_${("00" + (index + 1)).slice(-3)}.jpg?v=${VideoTrimService.thumbnailVersion}` : ""
                            }
                        }
                    }
                }

                // Dim the trimmed-away head and tail so the kept window pops.
                Rectangle {
                    x: 0
                    width: root.timeToX(root.inPoint, tl.width)
                    height: tl.height
                    color: Qt.rgba(0, 0, 0, 0.6)
                    radius: Appearance.rounding.small
                }

                Rectangle {
                    x: root.timeToX(root.outPoint, tl.width)
                    width: tl.width - x
                    height: tl.height
                    color: Qt.rgba(0, 0, 0, 0.6)
                    radius: Appearance.rounding.small
                }

                // Bright outline around the kept selection.
                Rectangle {
                    x: root.timeToX(root.inPoint, tl.width)
                    width: Math.max(0, root.timeToX(root.outPoint, tl.width) - x)
                    height: tl.height
                    color: "transparent"
                    radius: Appearance.rounding.small
                    border.width: 2
                    border.color: Colours.palette.m3primary
                }

                // Click-to-seek anywhere on the strip (handles, declared after,
                // sit above this and capture their own drags).
                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.durationSec <= 0)
                            return;
                        const t = Math.max(0, Math.min(tl.width, mouse.x)) / tl.width * root.durationSec;
                        player.position = Math.round(t * 1000);
                    }
                }

                // Playhead
                Rectangle {
                    visible: root.durationSec > 0
                    x: root.timeToX(player.position / 1000, tl.width) - width / 2
                    width: 2
                    height: tl.height
                    color: Colours.palette.m3onSurface
                }

                // In handle
                Rectangle {
                    id: inHandle
                    x: root.timeToX(root.inPoint, tl.width) - width / 2
                    width: 10
                    height: tl.height
                    radius: Appearance.rounding.small
                    color: Colours.palette.m3primary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.SizeHorCursor
                        drag.threshold: 0
                        onPositionChanged: {
                            if (!pressed || root.durationSec <= 0)
                                return;
                            const tx = mapToItem(tl, mouseX, 0).x;
                            const t = Math.max(0, Math.min(tl.width, tx)) / tl.width * root.durationSec;
                            root.inPoint = Math.max(0, Math.min(t, root.outPoint - root.minGap));
                            player.position = Math.round(root.inPoint * 1000);
                        }
                    }
                }

                // Out handle
                Rectangle {
                    id: outHandle
                    x: root.timeToX(root.outPoint, tl.width) - width / 2
                    width: 10
                    height: tl.height
                    radius: Appearance.rounding.small
                    color: Colours.palette.m3primary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.SizeHorCursor
                        drag.threshold: 0
                        onPositionChanged: {
                            if (!pressed || root.durationSec <= 0)
                                return;
                            const tx = mapToItem(tl, mouseX, 0).x;
                            const t = Math.max(0, Math.min(tl.width, tx)) / tl.width * root.durationSec;
                            root.outPoint = Math.min(root.durationSec, Math.max(t, root.inPoint + root.minGap));
                            player.position = Math.round(root.outPoint * 1000);
                        }
                    }
                }
            }

            // ── Footer: result span + actions ──────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.normal

                StyledText {
                    text: qsTr("Result ≈ %1").arg(root.fmt(root.outPoint - root.inPoint))
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                RaisedTextButton {
                    text: qsTr("Cancel")
                    onClicked: VideoTrimService.close()
                }

                RaisedIconTextButton {
                    icon: "content_cut"
                    text: VideoTrimService.trimming ? qsTr("Trimming…") : qsTr("Trim → clipboard")
                    disabled: VideoTrimService.trimming || root.durationSec <= 0
                    onClicked: VideoTrimService.trim(root.inPoint, root.outPoint)
                }
            }
        }
    }

    // Complete priming: pause the muted prime playback, park the head at the
    // start, and unmute. Invoked by whichever fires first — the first painted
    // frame (onPositionChanged) or the primeTimer fallback.
    function finishPriming(): void {
        if (root.primed)
            return;
        player.pause();
        player.position = Math.round(root.inPoint * 1000);
        root.primed = true;
    }

    // Toggle playback, snapping the playhead back into the kept region first so
    // play() always auditions [in, out] rather than wherever the head landed.
    function togglePlay(): void {
        if (player.playbackState === MediaPlayer.PlayingState) {
            player.pause();
        } else {
            if (player.position < root.inPoint * 1000 || player.position >= root.outPoint * 1000)
                player.position = Math.round(root.inPoint * 1000);
            player.play();
        }
    }
}
