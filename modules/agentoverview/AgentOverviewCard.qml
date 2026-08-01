pragma ComponentBehavior: Bound

import qs.modules.agentbar as AgentBar
import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// One agent monitoring card for the Agent Overview grid.
///
/// Pure read-model of a single bridge agent object — reuses AgentChipFor (the
/// canonical agent→chip adapter) for the animated sparkle, so the overview's
/// activity rendering is identical to the bottom bar's and can't drift. Click
/// focuses the agent's host window and dismisses the overlay.
StyledRect {
    id: root

    // intentional var: heterogeneous agent JS object from the AgentService bridge feed
    required property var agent

    readonly property string _state: root.agent.activity_state ?? ""
    readonly property bool needsPermission: root._state === "needs_permission"
    readonly property bool isActive: AgentOverviewService.isAgentActive(root.agent)
    readonly property bool isRemote: root.agent.remote === true
    readonly property int terminalPid: root.agent.terminal_pid ?? 0
    // Local agents focus their window on click; remote/orphan agents have none.
    readonly property bool focusable: !root.isRemote && root.terminalPid > 0
    // Conversation preview: prefer the shell's read-side backfill (fresh, full
    // transcript keyed by session_id — fills even long-dormant cards), falling
    // back to the bridge-pushed fields for remote agents. `conversations` is
    // passed explicitly, not read inside the service, so this binding
    // re-evaluates when the backfill lands.
    readonly property var convo: AgentOverviewService.conversationFor(root.agent, AgentOverviewService.conversations)
    readonly property string lastPrompt: root.convo.last_prompt ?? ""
    // intentional var: JS array of recent assistant text strings
    readonly property var lastMessages: root.convo.last_messages ?? []

    implicitWidth: Config.agentOverview.sizes.cardWidth
    implicitHeight: content.implicitHeight + Appearance.padding.large * 2

    radius: Appearance.rounding.normal
    color: Colours.palette.m3surfaceContainerHigh

    border.width: root.needsPermission ? 2 : 1
    border.color: {
        if (root.needsPermission)
            return Colours.palette.m3tertiary;
        if (root.isActive)
            return Colours.palette.m3primary;
        return Colours.palette.m3outlineVariant;
    }

    Behavior on border.color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    ColumnLayout {
        id: content

        // Anchored top/left/right, NOT anchors.fill: root.implicitHeight is
        // derived from content.implicitHeight, and filling would make content's
        // height depend back on root's. Harmless while the content was fixed
        // height; the wrapping conversation preview makes it variable. Same fix
        // as Dash.Calendar — see MEMORY.md, calendar popout sizing.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Appearance.padding.large
        spacing: Appearance.spacing.small

        // Header: sparkle + project + backend badge
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            AgentBar.AgentChipFor {
                Layout.alignment: Qt.AlignVCenter
                agent: root.agent
            }

            StyledText {
                Layout.fillWidth: true
                text: root.agent.project || "(no project)"
                color: Colours.palette.m3onSurface
                font.weight: Font.Bold
                font.pointSize: Appearance.font.size.normal
                elide: Text.ElideRight
            }

            StyledText {
                visible: (root.agent.agent_type ?? "") !== ""
                text: (root.agent.agent_type ?? "").toUpperCase()
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }
        }

        // Optional OSC title (only when set and distinct from project)
        StyledText {
            Layout.fillWidth: true
            visible: (root.agent.title ?? "") !== "" && root.agent.title !== root.agent.project
            text: root.agent.title ?? ""
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.small
            elide: Text.ElideRight
        }

        // Activity line + (when present) model / context%
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root._activityLabel()
                color: {
                    if (root.needsPermission)
                        return Colours.palette.m3tertiary;
                    if (root.isActive)
                        return Colours.palette.m3primary;
                    return Colours.palette.m3onSurfaceVariant;
                }
                font.pointSize: Appearance.font.size.small
                elide: Text.ElideRight
            }

            // model/context% are IDE-only enrichments (Phase 3): absent from the
            // bridge today, so these stay hidden until the IDE publishes them.
            StyledText {
                visible: (root.agent.model ?? "") !== ""
                text: root.agent.model ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }

            StyledText {
                visible: (root.agent.context_pct ?? -1) >= 0
                text: (root.agent.context_pct ?? 0) + "%"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }
        }

        // Status badges: remote / plan mode. (skip-perms intentionally omitted —
        // dangerous mode is the norm now and the badge was pure noise.)
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small
            visible: root.isRemote || root.agent.in_plan_mode === true

            MaterialIcon {
                visible: root.isRemote
                text: "cloud_queue"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }

            StyledText {
                visible: root.agent.in_plan_mode === true
                text: "plan"
                color: Colours.palette.m3tertiary
                font.pointSize: Appearance.font.size.small
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // Recent conversation: the user's last prompt + the agent's last few
        // assistant turns. Sourced from AgentOverviewService's read-side
        // transcript backfill when available, else the bridge-pushed fields —
        // check that service first when a preview looks wrong, not the bridge.
        // Hidden until either source has text (e.g. OpenCode, which doesn't yet
        // forward any).
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small
            visible: root.lastPrompt !== "" || root.lastMessages.length > 0

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.4
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.lastPrompt !== ""
                text: "▸ " + root.lastPrompt
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
                font.italic: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Repeater {
                model: root.lastMessages

                StyledText {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData
                    color: Colours.palette.m3onSurface
                    font.pointSize: Appearance.font.size.small
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Click-to-focus overlay (above content; AgentChipFor is a pure display
    // component with no interactive children, so this is safe — see ProjectGroup).
    MouseArea {
        anchors.fill: parent
        cursorShape: root.focusable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.focusable)
                AgentOverviewService.focusAgentAndHide(root.agent);
        }
    }

    /// Human-readable activity. activity_tool is already a human verb
    /// ("Editing"/"Reading"/"Running") from the bridge, so use it directly.
    function _activityLabel(): string {
        const s = root._state;
        const t = root.agent.activity_tool ?? "";
        if (s === "" || s === "idle")
            return "Idle";
        if (s === "working")
            return t !== "" ? t : "Working…";
        if (s === "thinking")
            return "Thinking…";
        if (s === "needs_permission")
            return t !== "" ? (t + " — needs permission") : "Needs permission";
        if (s === "starting")
            return "Starting…";
        if (s === "clearing")
            return "Clearing…";
        return s;
    }
}
