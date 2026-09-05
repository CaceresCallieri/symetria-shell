pragma ComponentBehavior: Bound

/// AgentChip bound to a single agent object. Maps the agent's fields onto the
/// chip's required properties in ONE place, so every callsite wires the chip
/// identically and can't drift.
AgentChip {
    id: root

    // intentional var: heterogeneous agent JS object from the Mesura thread projection
    required property var agent

    active: root.agent.active ?? false
    activityState: root.agent.activity_state ?? ""
    activityTool: root.agent.activity_tool ?? ""
    // Backend identity ("claude" | "opencode") — drives the chip accent color.
    // Absent/"" falls through to the Claude default in AgentChip, which is the
    // decided v1 behaviour for every Mesura thread: the broker contract excludes
    // provider identity, so the wire cannot say which backend runs a thread.
    agentType: root.agent.agent_type ?? ""
    // Constant, not a binding on AgentService. The STT target is addressed by
    // `terminal_pid`, and every row the bar draws now comes from Mesura Code,
    // which reports `terminal_pid: 0` — so the old binding could only ever
    // return false while holding the surviving bar to a service that exists
    // solely to feed dictation. Dictation is unaffected; only its indicator
    // here is gone, and it returns when Mesura reports a dictation target.
    //
    // Paired with AgentChip.qml, which correspondingly stopped forwarding
    // `sttIsTranscribing`. Restore BOTH together — either one alone leaves the
    // shared chip's STT branch unreachable. Issue #64.
    isSttTarget: false
}
