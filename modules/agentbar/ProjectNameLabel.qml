import qs.components
import qs.services
import qs.config
import QtQuick

/// Project-name label for the agent bar pills — shared by the standalone ProjectGroup
/// (Mode 2) and the merged AgentChipGroup (Mode 3) so the two bar layouts can never
/// drift apart typographically.
///
/// Set in all-caps: at bar scale a capitalised run reads as a deliberate label rather
/// than as a stray word, and it separates the project name from the lowercase window
/// titles around it.
StyledText {
    // Caps have no descenders and a uniform cap-height, so at an equal point size they
    // read visibly larger than mixed case. Drop two points to keep the optical size
    // matched to the neighbouring chips, and add a touch of tracking — tightly set
    // uppercase runs lose legibility without it.
    //
    // The `- 2` is deliberately the same expression the workspace badge icons use in
    // ProjectGroup.qml, so label and badge stay the same size; don't clamp or rescale
    // it here alone. letterSpacing is likewise a flat constant, not scaled: 0.3px of
    // tracking is an optical correction for the caps, not a size-proportional metric.
    font.capitalization: Font.AllUppercase
    font.pointSize: Appearance.font.size.small - 2
    font.letterSpacing: 0.3
    font.weight: Font.Bold
    color: Colours.palette.m3primary
}
