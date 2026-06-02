pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Per-project pill: styled container with project name and agent chips.
PillSurface {
    id: root

    required property string project
    required property var agents  // Array of agent objects for this project

    // Remote detection: true when any agent in this group is tunneled via SSH
    readonly property bool isRemote: agents.some(a => a.remote === true)

    // Workspace badge: pick representative workspace for this group
    readonly property var wsInfo: AgentService.workspaceForAgents(agents)
    readonly property string wsIcon: wsInfo ? AgentService.workspaceIconForWsId(wsInfo.id) : ""
    readonly property var parsedWsIcon: wsIcon ? Icons.parseIcon(wsIcon) : null
    readonly property bool hasWsBadge: (parsedWsIcon !== null && parsedWsIcon.iconText !== "") || isRemote

    // Active when this group's workspace matches the focused workspace
    // Remote projects are never "current" (no local Hyprland window)
    readonly property bool isCurrentProject: !isRemote && wsInfo !== null && wsInfo.id === Hypr.activeWsId

    // True when any agent in this group needs permission approval
    readonly property bool hasPermissionNeeded:
        root.agents.some(a => (a.activity_state ?? "") === "needs_permission")

    // True when any agent in this group is the STT injection target
    readonly property bool hasSttTarget:
        AgentService.sttTargetTerminalPid > 0 && root.agents.some(a => AgentService.isAgentSttTarget(a))

    // --- Sweep animation state ---
    property real _sweepPhase: 0.0  // 0.0–1.0, one full revolution
    readonly property color _sweepColor: hasPermissionNeeded
        ? Colours.palette.m3tertiary
        : Colours.palette.m3primary

    // Representative terminal PID: active agent's, or first agent's
    readonly property int terminalPid: AgentService.representativeAgent(agents)?.terminal_pid ?? 0

    // Pre-computed pill styles — not reactive to pillStyle config hot-reload (requires shell restart)
    readonly property var focusedStyle: Colours.pillStyle(Colours.palette.m3primary, 1.0)
    readonly property var unfocusedStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, 0.15)

    color: isCurrentProject ? focusedStyle.background : unfocusedStyle.background
    radius: Appearance.rounding.full
    borderWidth: hasPermissionNeeded ? 2 : 1
    borderColor: {
        if (hasPermissionNeeded) return Colours.palette.m3tertiary;
        if (isCurrentProject) return focusedStyle.border;
        return unfocusedStyle.border;
    }
    // PillSurface's body is a StyledClippingRect, which already clips children to
    // the rounded capsule shape — this clips the outer half of sweepCanvas's halo
    // stroke, producing the inward-glow effect we want. No extra clip flag needed.

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
        onTriggered: {
            root._sweepPhase += frameTime / 4.0;
            if (root._sweepPhase >= 1024.0)
                root._sweepPhase -= 1024.0;
            sweepCanvas.requestPaint();
        }
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

        // Workspace badge (Roman numeral, Material icon, or cloud for remote)
        Loader {
            id: wsBadge

            active: root.hasWsBadge
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: root.isRemote ? wsRemoteIcon
                : (root.parsedWsIcon?.useMaterial ? wsMatIcon : wsTextIcon)

            Component {
                id: wsRemoteIcon

                MaterialIcon {
                    text: "cloud_queue"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.small - 2
                }
            }

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
            Layout.alignment: Qt.AlignVCenter
            text: root.project
            color: Colours.palette.m3primary
            font.weight: Font.Bold
            font.pointSize: Appearance.font.size.small
        }

        // Agent chips. Use AgentChipFor (not a bare AgentChip) so the agent→chip
        // field mapping — including the backend agent_type that drives the accent
        // color — lives in exactly one place and can't drift between callsites.
        Repeater {
            // ScriptModel keyed on the stable agent id — see AgentChipGroup for the full
            // rationale. A plain JS array forces a full delegate reset on every bridge
            // emission (fresh-parsed objects), flashing busy sparkles onto idle siblings.
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

        const bw = root.borderWidth;
        const inset = bw / 2;
        const ew = w - bw;      // effective width inside border
        const eh = h - bw;      // effective height inside border
        const er = eh / 2;      // pill end-cap radius
        if (ew < eh) return;

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
