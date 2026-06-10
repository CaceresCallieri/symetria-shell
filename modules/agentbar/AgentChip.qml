import Symmetria.Agents.UI as AgentsUI
import qs.services
import qs.config

/// Thin adapter over the shared Symmetria.Agents.UI AgentChip (the canonical
/// implementation, also consumed by Symmetria IDE — see
/// ~/projects/symmetria-agents-ui). Binds the shell's theme/config singletons
/// into the module's injected properties so callsites (AgentChipFor and its
/// users) keep the exact pre-extraction API: the required props
/// (active/activityState/activityTool/isSttTarget/agentType) stay required on
/// the derived type and pass through unchanged.
AgentsUI.AgentChip {
    size: Appearance.font.size.small * 1.4
    sttIsTranscribing: AgentService.sttIsTranscribing
    crossfadeDuration: Appearance.anim.durations.normal
}
