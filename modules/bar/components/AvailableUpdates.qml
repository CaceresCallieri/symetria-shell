pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.misc
import qs.services
import qs.config
import QtQuick

MouseArea {
    id: root

    property color colour: Colours.palette.m3tertiary

    // Live count while a run is in progress; otherwise the poller's count.
    // `finished` is included so the indicator holds at 0 ("done") instead of
    // flashing the stale pre-update poller count during the window between
    // process exit and the post-run Updates.refresh() recount completing.
    readonly property int displayCount: UpdateRunner.running || UpdateRunner.finished ? UpdateRunner.remaining : Updates.totalUpdates

    // Tooltip text with breakdown by source (Pacman + AUR only)
    readonly property string tooltipText: {
        if (!Updates.hasData)
            return "Loading...";

        // No Nerd Font glyphs here: Tooltip exposes no font-family control, so
        // this string renders in whatever face the tooltip uses — which is no
        // longer guaranteed to carry the private-use ranges. The labels already
        // say what the glyphs said.
        const pacmanLine = `Pacman: ${Updates.pacmanUpdates}`;
        const aurLine = `AUR: ${Updates.aurUpdates}`;
        const total = Updates.pacmanUpdates + Updates.aurUpdates;
        const totalLine = `Total: ${total}`;

        return `${pacmanLine}\n${aurLine}\n${totalLine}`;
    }

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    // Click to start the update. The popout then shows live progress in place; the
    // run continues whether or not the popout is hovered. The single askpass password
    // prompt inside the run is the confirmation gate, so an accidental click can't
    // silently update the system.
    onClicked: {
        if (UpdateRunner.running)
            return; // already running — progress is visible in the popout
        if (UpdateRunner.finished) {
            UpdateRunner.acknowledge(); // clear a prior result; second click will start a new run
            return;
        }
        if (Updates.totalUpdates > 0)
            UpdateRunner.start();
        else
            Updates.refresh(); // nothing to do — just re-check
    }

    // Subscribe to Updates service when active
    Ref {
        service: Updates
    }

    Row {
        id: content

        spacing: Appearance.spacing.small

        MaterialIcon {
            id: statusIcon

            anchors.verticalCenter: parent.verticalCenter

            // sync glyph while updating, error/check on finish, download otherwise.
            text: {
                if (UpdateRunner.running)
                    return "sync";
                if (UpdateRunner.phase === "error")
                    return "error";
                return root.displayCount === 0 ? "check_box" : "download";
            }
            color: UpdateRunner.phase === "error" ? Colours.palette.m3error : root.colour

            // Spin the sync glyph while a run is in progress.
            RotationAnimation {
                target: statusIcon
                property: "rotation"
                running: UpdateRunner.running
                from: 0
                to: 360
                duration: 1200
                loops: Animation.Infinite
                onRunningChanged: if (!running)
                    statusIcon.rotation = 0
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.displayCount > 0

            text: root.displayCount.toString()
            font.pointSize: Appearance.font.size.smaller
            font.family: Appearance.font.family.mono
            color: root.colour
        }
    }

    Tooltip {
        target: root
        text: root.tooltipText
    }
}
