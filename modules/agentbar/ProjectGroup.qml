pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import QtQuick
import QtQuick.Layouts

/// Per-project pill: glassmorphism container with project name and agent chips.
StyledRect {
    id: root

    required property string project
    required property var agents  // Array of agent objects for this project

    // Workspace badge: pick representative workspace for this group
    readonly property var wsInfo: AgentService.workspaceForAgents(agents)
    readonly property string wsIcon: wsInfo ? AgentService.workspaceIconForWsId(wsInfo.id) : ""
    readonly property var parsedWsIcon: wsIcon ? Icons.parseIcon(wsIcon) : null
    readonly property bool hasWsBadge: parsedWsIcon !== null && parsedWsIcon.iconText !== ""

    // Active when this group's workspace matches the focused workspace
    readonly property bool isCurrentProject: wsInfo !== null && wsInfo.id === Hypr.activeWsId

    // True when any agent in this group needs permission approval
    readonly property bool hasPermissionNeeded:
        root.agents.some(a => (a.activity_state ?? "") === "needs_permission")

    // True when any agent in this group is the STT injection target
    readonly property bool hasSttTarget: {
        if (AgentService.sttTargetTerminalPid <= 0) return false;
        return root.agents.some(a => {
            if ((a.terminal_pid ?? 0) !== AgentService.sttTargetTerminalPid) return false;
            if (AgentService.sttTargetBufId === -1) return a.active ?? false;
            return (a.buf ?? -1) === AgentService.sttTargetBufId;
        });
    }

    // --- Sweep animation state ---
    property real _sweepPhase: 0.0  // 0.0–1.0, one full revolution
    readonly property color _sweepColor: hasPermissionNeeded
        ? Colours.palette.m3tertiary
        : Colours.palette.m3primary

    // Representative terminal PID: active agent's, or first agent's
    readonly property int terminalPid: AgentService.representativeAgent(agents)?.terminal_pid ?? 0

    color: isCurrentProject
        ? Colours.glassmorphism(Colours.palette.m3primary, 1.0).background
        : Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, 0.15).background
    radius: Appearance.rounding.full
    border.width: hasPermissionNeeded ? 2 : 1
    border.color: {
        if (hasPermissionNeeded) return Colours.palette.m3tertiary;
        if (isCurrentProject) return Colours.glassmorphism(Colours.palette.m3primary, 1.0).border;
        return Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, 0.15).border;
    }
    clip: true

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.width {
        Anim {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.color {
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

    // KNOWN ISSUE: The sweep animation has a subtle periodic hitch that could not
    // be resolved. Approaches tried:
    //   1. NumberAnimation with loops: Animation.Infinite — hitches at loop boundary
    //      (1-frame stall when value jumps from `to` back to `from`)
    //   2. FrameAnimation with phase wrapping (% 1.0) — hitches at modulo wrap point
    //      (lineDashOffset jumps ~perimeter in one frame; QML Canvas may not reduce
    //       the offset modulo the dash array length before rendering)
    //   3. FrameAnimation without wrapping (current) — phase grows monotonically,
    //      no discontinuity in lineDashOffset, but a subtle hitch persists
    //
    // The hitch may be inherent to QML Canvas 2D repaint scheduling (clearRect +
    // full path reconstruction + dual-pass stroke every frame). Potential alternatives
    // not yet tried: Shape + ShapePath with animated dashOffset (GPU scene graph,
    // but risky in Quickshell layer-shell at small sizes — see MEMORY.md), or a
    // pre-rendered rotating Image with OpacityMask.
    FrameAnimation {
        running: root.hasSttTarget
        onTriggered: root._sweepPhase += frameTime / 4.0
        onRunningChanged: if (!running) root._sweepPhase = 0.0
    }

    // Rotating border glow overlay for STT injection target
    Canvas {
        id: sweepCanvas

        anchors.fill: parent
        opacity: root.hasSttTarget ? 1.0 : 0.0
        visible: opacity > 0
        renderStrategy: Canvas.Cooperative

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }
        }

        onPaint: root._drawSweep(getContext("2d"), width, height)

        Connections {
            function on_SweepPhaseChanged(): void { sweepCanvas.requestPaint(); }
            function on_SweepColorChanged(): void { sweepCanvas.requestPaint(); }
            target: root
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

        // Workspace badge (Roman numeral or Material icon)
        Loader {
            id: wsBadge

            active: root.hasWsBadge
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: root.parsedWsIcon?.useMaterial ? wsMatIcon : wsTextIcon

            Component {
                id: wsMatIcon

                MaterialIcon {
                    text: root.parsedWsIcon?.iconText ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.small - 2
                }
            }

            Component {
                id: wsTextIcon

                StyledText {
                    text: root.parsedWsIcon?.iconText ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font.weight: Font.DemiBold
                    font.pointSize: Appearance.font.size.small - 2
                }
            }
        }

        // Project name label
        StyledText {
            text: root.project
            color: Colours.palette.m3primary
            font.weight: Font.Bold
            font.pointSize: Appearance.font.size.small
        }

        // Agent chips
        Repeater {
            model: root.agents

            AgentChip {
                required property var modelData
                required property int index

                instanceNum: index + 1
                active: modelData.active ?? false
                activityState: modelData.activity_state ?? ""
                activityTool: modelData.activity_tool ?? ""
                isSttTarget: {
                    if (AgentService.sttTargetTerminalPid <= 0) return false;
                    if ((modelData.terminal_pid ?? 0) !== AgentService.sttTargetTerminalPid) return false;
                    // -1 = agent had no buf at start-time; highlight the active (representative) agent
                    if (AgentService.sttTargetBufId === -1) return modelData.active ?? false;
                    return (modelData.buf ?? -1) === AgentService.sttTargetBufId;
                }
            }
        }

        // Right padding
        Item {
            implicitWidth: Appearance.spacing.smaller
            implicitHeight: 1
        }
    }

    // Click-to-focus overlay — sits above RowLayout content in z-order.
    // Safe because AgentChip is a pure display component (no interactive children).
    // If interactive elements are added to AgentChip later, restructure this
    // (e.g., use a TapHandler on root, or move interactivity into AgentChip).
    MouseArea {
        anchors.fill: parent
        cursorShape: root.terminalPid > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.terminalPid > 0)
                AgentService.focusTerminal(root.terminalPid);
        }
    }

    /// Draws a rotating dashed stroke along the pill border.
    /// Two passes: wide low-opacity halo + narrow high-opacity core = glow effect.
    function _drawSweep(ctx: var, w: real, h: real): void {
        ctx.clearRect(0, 0, w, h);
        if (w <= 0 || h <= 0) return;

        const bw = root.border.width;
        const inset = bw / 2;
        const ew = w - bw;      // effective width inside border
        const eh = h - bw;      // effective height inside border
        const er = eh / 2;      // pill end-cap radius

        const perimeter = 2 * (ew - eh) + Math.PI * eh;
        const segLen = perimeter * 0.18;
        const offset = root._sweepPhase * perimeter;

        function pillPath() {
            ctx.beginPath();
            ctx.moveTo(inset + er, inset);
            ctx.lineTo(inset + ew - er, inset);
            ctx.arc(inset + ew - er, inset + er, er, -Math.PI / 2, Math.PI / 2);
            ctx.lineTo(inset + er, inset + eh);
            ctx.arc(inset + er, inset + er, er, Math.PI / 2, 3 * Math.PI / 2);
            ctx.closePath();
        }

        const c = root._sweepColor;
        ctx.setLineDash([segLen, perimeter - segLen]);
        ctx.lineDashOffset = -offset;
        ctx.lineCap = "round";

        // Pass 1: soft halo
        ctx.lineWidth = 5;
        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.18);
        pillPath();
        ctx.stroke();

        // Pass 2: bright core
        ctx.lineWidth = 2;
        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.75);
        pillPath();
        ctx.stroke();
    }
}
