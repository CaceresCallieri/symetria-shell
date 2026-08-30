import Symmetria.Agents.UI as AgentsUI
import qs.config

/// Thin adapter over the shared Symmetria.Agents.UI AgentChip (the canonical
/// implementation, also consumed by Symmetria IDE — see
/// ~/projects/symmetria-agents-ui). Binds the shell's theme/config singletons
/// into the module's injected properties so callsites (AgentChipFor and its
/// users) keep the exact pre-extraction API: the required props
/// (active/activityState/activityTool/isSttTarget/agentType) stay required on
/// the derived type and pass through unchanged.
///
/// `sttIsTranscribing` is deliberately left at the module default. It used to
/// track `AgentService.sttIsTranscribing`, but the chip only ever animated on
/// it while `isSttTarget` was true, and no row this bar draws can be an STT
/// target any more — see AgentChipFor.
AgentsUI.AgentChip {
    size: Appearance.font.size.small * 1.4
    crossfadeDuration: Appearance.anim.durations.normal
}
