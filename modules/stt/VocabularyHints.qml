pragma ComponentBehavior: Bound

import qs.components
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

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight

    // Defer focus to next event loop tick so the Wayland layer-shell
    // keyboard grab has time to activate before we request focus.
    onVisibleChanged: {
        if (visible)
            Qt.callLater(hintInput.forceActiveFocus);
    }

    StyledRect {
        id: container

        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: root.minWidth
        implicitHeight: hintInput.implicitHeight

        radius: Appearance.rounding.normal
        color: "transparent"

        StyledTextField {
            id: hintInput

            anchors.centerIn: parent
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
}
