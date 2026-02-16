pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// KeyChords service — loads chord groups from chords.json
/// and manages active group state for the overlay UI.
///
/// Chord groups are defined in ~/.config/symmetria/chords.json.
/// Each group has a title and array of {key, label, command} entries.
/// Commands are executed via "sh -c" for shell expansion ($HOME, pipes, etc.).
Singleton {
    id: root

    /// Whether a chord group overlay is currently shown.
    property bool active: false

    /// Current group identifier (e.g., "screenshot").
    readonly property string activeGroup: _activeGroup
    property string _activeGroup: ""

    /// Display title for the current group (e.g., "Screenshot").
    readonly property string activeGroupTitle: _activeGroupTitle
    property string _activeGroupTitle: ""

    /// JS array of {key, label, command} for the current group.
    readonly property var activeChords: _activeChords
    property var _activeChords: []

    /// All parsed chord groups from JSON. Map of groupName → {title, chords[]}.
    property var chordGroups: ({})

    /// Activate a chord group by name. Toggles off if same group is already active.
    function activate(group: string): void {
        if (!group) {
            console.warn("[KeyChords] activate() called with empty group");
            return;
        }

        // Toggle behavior: same group → dismiss
        if (active && _activeGroup === group) {
            dismiss();
            return;
        }

        const groupData = chordGroups[group];
        if (!groupData) {
            console.warn("[KeyChords] Unknown chord group:", group);
            return;
        }

        if (!groupData.chords || groupData.chords.length === 0) {
            console.warn("[KeyChords] Chord group is empty:", group);
            return;
        }

        _activeGroup = group;
        _activeGroupTitle = groupData.title || group;
        _activeChords = groupData.chords;
        active = true;
    }

    /// Dismiss the overlay without executing any command.
    function dismiss(): void {
        active = false;
        _activeGroup = "";
        _activeGroupTitle = "";
        _activeChords = [];
    }

    /// Handle a key press. Returns true if matched (command executed).
    function handleKey(key: string): bool {
        if (!active || !_activeChords || _activeChords.length === 0)
            return false;

        const normalized = key.toUpperCase();

        for (const chord of _activeChords) {
            if (chord.key.toUpperCase() === normalized) {
                const command = chord.command;
                dismiss();
                executeCommand(command);
                return true;
            }
        }

        return false;
    }

    function executeCommand(command: string): void {
        commandRunner.command = ["sh", "-c", command];
        commandRunner.running = true;
    }

    Process {
        id: commandRunner

        onExited: (code, status) => {
            if (code !== 0)
                console.warn("[KeyChords] Command exited with code", code);
        }
    }

    FileView {
        id: chordsFile

        path: `${Paths.config}/chords.json`
        watchChanges: true

        onFileChanged: reload()

        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.chordGroups = validateGroups(parsed);
            } catch (e) {
                console.error("[KeyChords] Failed to parse chords.json:", e.message);
            }
        }

        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.chordGroups = {};
            } else {
                console.warn("[KeyChords] Failed to read chords.json:", FileViewError.toString(err));
            }
        }
    }

    /// Validate and sanitize parsed JSON into clean chord groups.
    function validateGroups(parsed: var): var {
        const result = {};

        for (const [name, group] of Object.entries(parsed)) {
            if (!group || typeof group !== "object") continue;
            if (!Array.isArray(group.chords)) continue;

            const validChords = group.chords.filter(c =>
                c && typeof c.key === "string" && c.key.length === 1 &&
                typeof c.label === "string" && c.label.length > 0 &&
                typeof c.command === "string" && c.command.length > 0
            );

            if (validChords.length > 0) {
                result[name] = {
                    title: typeof group.title === "string" ? group.title : name,
                    chords: validChords
                };
            }
        }

        return result;
    }
}
