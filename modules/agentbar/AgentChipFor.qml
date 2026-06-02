pragma ComponentBehavior: Bound

import qs.services
import QtQuick

/// AgentChip bound to a single bridge agent object. Maps the agent's fields onto the
/// chip's four required properties in ONE place, so every callsite (workspace pills,
/// hosted-window icons, orphan/remote slots) wires the chip identically and can't drift.
AgentChip {
    id: root

    // intentional var: heterogeneous agent JS object from AgentService bridge JSON
    required property var agent

    active: root.agent.active ?? false
    activityState: root.agent.activity_state ?? ""
    activityTool: root.agent.activity_tool ?? ""
    // Backend identity ("claude" | "opencode") — drives the chip accent color.
    // Absent/"" (legacy snapshots) falls through to the Claude default in AgentChip.
    agentType: root.agent.agent_type ?? ""
    isSttTarget: AgentService.isAgentSttTarget(root.agent)
}
