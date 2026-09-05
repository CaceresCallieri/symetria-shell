import qs.components
import qs.services
import qs.config
import QtQuick

/// Project-name label for the agent bar pills, used by ProjectGroup. It was
/// extracted so the standalone and merged bar layouts could not drift apart
/// typographically; the merged layout went out with Symmetria IDE, so the label
/// now has one consumer and is kept separate only to hold this reasoning.
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
    // letterSpacing is a flat constant, not scaled: 0.3px of tracking is an optical
    // correction for the caps, not a size-proportional metric.
    font.capitalization: Font.AllUppercase
    font.pointSize: Appearance.font.size.small - 2
    font.letterSpacing: 0.3
    font.weight: Font.Bold
    color: Colours.palette.m3primary
}
