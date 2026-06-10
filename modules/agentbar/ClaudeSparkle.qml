import Symmetria.Agents.UI as AgentsUI
import qs.config

/// Thin adapter over the shared Symmetria.Agents.UI ClaudeSparkle (the
/// canonical implementation + sprite assets — see
/// ~/projects/symmetria-agents-ui). Kept so SpritePreview.qml (the
/// /test-sprite harness) and any future shell callsite get the shell's
/// themed size without each binding it manually. All other props
/// (color/mode/speedFactor/desyncLoop/skipToEnd()/restart()) are the shared
/// type's own API, unchanged.
AgentsUI.ClaudeSparkle {
    size: Appearance.font.size.small * 1.4
}
