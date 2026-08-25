pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Small superscript-style count badge showing the number of active vocab
/// hints that will be sent with the next STT submission. Designed to
/// overlay the top-right corner of the delivery-mode pill so the count is
/// visible without opening the drawer or hovering the bar embed — the
/// keyboard-driven workflow needs persistent feedback about how many hints
/// are queued.
///
/// Click toggles SttService.vocabHintsVisible, giving mouse users the same
/// shortcut as Alt+W (reveal the hint input, which also surfaces the chip
/// row in the drawer Content card).
Item {
    id: root

    readonly property int count: SttService.sessionVocabHints.length

    // Hidden in audio mode — vocab hints only apply to STT transcription.
    // Hidden when no hints are queued.
    // Fade with opacity, not visible, so the Behavior animates the
    // transition across the empty boundary instead of snapping.
    readonly property bool _isSttMode: RecordingSessionManager.activeMode === "stt"
    opacity: _isSttMode && count > 0 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {}
    }

    // Match PillButton's matte/glass base so the badge reads as a
    // visually tethered companion to the delivery pill rather than an
    // accent-colored notification dot.
    // intentional var: heterogeneous JS { background, border }
    readonly property var _style: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    // Shrink the whole badge to ~85% of the base pill size so it reads
    // as a secondary/supplementary indicator next to the delivery pill.
    // Scaling the underlying font + padding values (rather than using
    // `scale: 0.85`) keeps implicitWidth/Height in sync so the RowLayout
    // slot doesn't leave empty space around a scaled render.
    readonly property real _scale: 0.85
    readonly property real _hPad: Appearance.padding.small * _scale
    readonly property real _vPad: Appearance.padding.small * 0.5 * _scale

    implicitWidth: Math.max(countText.implicitWidth + _hPad * 2, implicitHeight)
    implicitHeight: countText.implicitHeight + _vPad * 2

    StyledRect {
        id: badgeBg

        anchors.fill: parent
        radius: Appearance.rounding.full
        color: root._style.background
        border.width: 1
        border.color: root._style.border

        StyledText {
            id: countText

            anchors.centerIn: parent
            text: root.count
            color: Colours.palette.m3onSurface
            // Additional 0.9 multiplier on the digit itself (separate from
            // root._scale) so the number reads slightly smaller than the
            // pill suggests — padding stays at the _scale-governed value.
            font.pointSize: Appearance.font.size.smaller * root._scale * 0.9
            font.weight: Font.Bold
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Use toggleVocabHints() rather than direct property assignment —
            // it guards against toggling when there is no active recording.
            onClicked: SttService.toggleVocabHints()
        }
    }
}
