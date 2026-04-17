pragma ComponentBehavior: Bound

import qs.components.controls
import qs.services
import qs.config
import QtQuick

/// Text input for adding per-session vocabulary hints during STT recording.
///
/// Shows below the STT card when toggled via Alt+W keybind. Type a word
/// and press Enter to add it as a hint chip (displayed in the Content card).
/// Chips persist in the card even after this input is closed.
Item {
    id: root

    readonly property int minWidth: 220

    implicitWidth: hintInput.implicitWidth
    implicitHeight: hintInput.implicitHeight

    // Kick focus whenever this item becomes visible. Two trigger points are
    // needed because `onVisibleChanged` only fires on CHANGES, not on initial
    // creation — when the popout is loaded async fresh, VocabularyHints is
    // mounted with visible=true from the start and the signal never fires.
    //
    // Component.onCompleted covers the fresh-load path (popout was closed).
    // onVisibleChanged covers the toggle-while-open path (popout already
    // open from hover, FadeTransition.show flips false→true).
    Component.onCompleted: {
        if (visible)
            _kickFocus();
    }

    onVisibleChanged: {
        if (visible)
            _kickFocus();
        else
            focusRetryTimer.stop();
    }

    function _kickFocus(): void {
        focusRetryTimer.attempts = 0;
        focusRetryTimer.restart();
    }

    Timer {
        id: focusRetryTimer

        property int attempts: 0
        readonly property int maxAttempts: 10

        interval: 50
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            attempts++;
            hintInput.forceActiveFocus();
            if (hintInput.activeFocus || attempts >= maxAttempts)
                stop();
        }
    }

    StyledTextField {
        id: hintInput

        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: root.minWidth
        width: root.minWidth - Appearance.padding.large * 2
        horizontalAlignment: TextInput.AlignHCenter
        placeholderText: SttService.sessionVocabHints.length === 0
            ? "Type hint word"
            : "Add another..."
        font.pointSize: Appearance.font.size.small

        onAccepted: {
            if (text.trim() !== "") {
                // Support comma-separated batch entry
                const words = text.split(",");
                for (const word of words)
                    SttService.addSessionHint(word);
                clear();
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Backspace && text === "" && SttService.sessionVocabHints.length > 0) {
                SttService.removeSessionHint(SttService.sessionVocabHints.length - 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                SttService.vocabHintsVisible = false;
                event.accepted = true;
            }
        }
    }
}
