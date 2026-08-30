pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Per-project pill: styled container with project name and agent chips.
///
/// The pill used to carry three more things, all of them joins onto a local
/// Hyprland window that only a Symmetria IDE agent ever had: a workspace badge,
/// a focused/unfocused background driven by the active workspace, and
/// click-to-focus on the hosting terminal. A Mesura Code thread has no window
/// — `SymmetriaThreads` reports `terminal_pid: 0` for every row by design — so
/// all three were unreachable once the IDE's source was removed, and they went
/// with it rather than staying as bindings that can never be true.
///
/// The same argument retired the STT target sweep: it matched a row against
/// `AgentService.sttTargetTerminalPid`, which no surviving row can equal.
/// Dictation itself is untouched; only its indicator in this bar is gone. It
/// comes back when dictation reports a Mesura target — see issue #64.
PillSurface {
    id: root

    required property string project
    required property var agents  // Array of agent objects for this project

    // True when any agent in this group needs permission approval
    readonly property bool hasPermissionNeeded: root.agents.some(a => (a.activity_state ?? "") === "needs_permission")

    // Pre-computed pill style. This IS live across theme switches: QML captures
    // binding dependencies dynamically, so Colours.pillStyle() re-evaluates when
    // Theme.material changes — no restart needed.
    readonly property var pillStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, 0.15)

    color: pillStyle.background
    radius: Appearance.rounding.full
    borderWidth: hasPermissionNeeded ? 2 : 1
    borderColor: hasPermissionNeeded ? Colours.palette.m3tertiary : pillStyle.border

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    Behavior on borderWidth {
        Anim {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    Behavior on borderColor {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    implicitHeight: Config.agentbar.sizes.innerHeight
    implicitWidth: content.implicitWidth

    Behavior on implicitWidth {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
    }

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        // Left padding
        Item {
            implicitWidth: Appearance.spacing.smaller
            implicitHeight: 1
        }

        // Project name label
        ProjectNameLabel {
            Layout.alignment: Qt.AlignVCenter
            text: root.project
        }

        // Agent chips. Use AgentChipFor (not a bare AgentChip) so the agent→chip
        // field mapping — including the backend agent_type that drives the accent
        // color — lives in exactly one place and can't drift between callsites.
        Repeater {
            // ScriptModel keyed on the stable agent id. A plain JS array forces a
            // full delegate reset on every socket emission (fresh-parsed objects),
            // flashing busy sparkles onto idle siblings.
            // See docs/qml-pitfalls.md (agent-chip delegate identity).
            model: ScriptModel {
                values: root.agents
                objectProp: "id"
            }

            AgentChipFor {
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                agent: modelData
            }
        }

        // Right padding
        Item {
            implicitWidth: Appearance.spacing.smaller
            implicitHeight: 1
        }
    }
}
