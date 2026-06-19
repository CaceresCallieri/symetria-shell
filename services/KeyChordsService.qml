pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

/// KeyChords service — loads chord groups from chords.json
/// and manages active group state for the overlay UI.
///
/// Chord groups are defined in ~/.config/symmetria/chords.json.
/// Each group has a title and array of {key, label, command?, group?} entries.
/// Use `command` for shell execution or `group` to navigate to a sub-group.
/// If both are present, `group` takes precedence.
/// Commands are executed via "sh -c" for shell expansion ($HOME, pipes, etc.).
///
/// A group may instead declare an `expand` object to be generated from the
/// shared top-level `_workspaces` list (defined ONCE, reused by every menu) —
/// see expandWorkspaceGroups() for the template contract.
Singleton {
    id: root

    /// Whether a chord group overlay is currently shown.
    property bool active: false

    /// Current group identifier (e.g., "screenshot").
    readonly property string activeGroup: _activeGroup
    property string _activeGroup: ""

    /// Target monitor — captured at activation so the overlay shows only on
    /// the monitor that was focused when the chord was triggered.
    readonly property var targetMonitor: _targetMonitor
    property var _targetMonitor: null

    /// Display title for the current group (e.g., "Screenshot").
    readonly property string activeGroupTitle: _activeGroupTitle
    property string _activeGroupTitle: ""

    /// JS array of {key, label, command?, group?} for the current group.
    readonly property var activeChords: _activeChords
    property var _activeChords: []

    /// All parsed chord groups from JSON. Map of groupName → {title, chords[]}.
    property var chordGroups: ({})

    /// Navigation stack for sub-group back-navigation.
    /// Each entry is a group name. Escape pops back; empty stack → dismiss.
    property var _groupHistory: []

    /// Activate a chord group by name. Toggles off if same group is already active.
    /// Note: the toggle-dismiss applies to sub-groups too — navigating to the same
    /// group twice in a row (e.g., pressing the same chord key again) dismisses the overlay.
    function activate(group: string): void {
        console.warn("[KeyChords:Service] activate() called with group:", group, "| current active:", active, "| current group:", _activeGroup);
        if (!group) {
            console.warn("[KeyChords:Service] activate() called with empty group");
            return;
        }

        // Toggle behavior: same group → dismiss
        if (active && _activeGroup === group) {
            console.warn("[KeyChords:Service] Toggle-dismiss: same group, dismissing");
            dismiss();
            return;
        }

        const groupData = chordGroups[group];
        if (!groupData) {
            console.warn("[KeyChords:Service] Unknown chord group:", group, "| available groups:", Object.keys(chordGroups));
            return;
        }

        // Defensive: validateGroups guarantees chords is non-empty, but guard against
        // direct mutations of chordGroups outside the normal load/validate path.
        if (!groupData.chords || groupData.chords.length === 0) {
            console.warn("[KeyChords:Service] Chord group is empty:", group);
            return;
        }

        _activeGroup = group;
        _activeGroupTitle = groupData.title || group;
        _activeChords = groupData.chords;
        // Capture target monitor only on initial activation, not on sub-group navigation
        if (!active)
            _targetMonitor = Hypr.focusedMonitor;
        active = true;
        console.warn("[KeyChords:Service] Activated group:", group, "| chords:", groupData.chords.length, "| active is now:", active, "| targetMonitor:", targetMonitor?.name ?? "null");
    }

    /// Dismiss the overlay without executing any command. Clears navigation history.
    function dismiss(): void {
        active = false;
        _activeGroup = "";
        _activeGroupTitle = "";
        _activeChords = [];
        _groupHistory = [];
        _targetMonitor = null;
    }

    /// Navigate back to the parent chord group, or dismiss if at the top level.
    function navigateBack(): void {
        if (_groupHistory.length > 0) {
            const parent = _groupHistory.pop();
            _groupHistory = _groupHistory; // trigger binding update
            activate(parent);
        } else {
            dismiss();
        }
    }

    /// Dispatch a matched chord — either navigate to a sub-group or execute a command.
    /// Centralizes dispatch logic for both keyboard (handleKey) and mouse (Overlay click) paths.
    /// If a chord has both `group` and `command`, `group` takes precedence.
    function dispatchChord(chord: var): void {
        if (chord.group) {
            _groupHistory.push(_activeGroup);
            _groupHistory = _groupHistory; // trigger binding update
            activate(chord.group);
        } else {
            dismiss();
            _executeCommand(chord.command);
        }
    }

    /// Handle a key press. Returns true if matched (command executed or group navigated).
    function handleKey(key: string): bool {
        if (!active || !_activeChords || _activeChords.length === 0)
            return false;

        const normalized = key.toUpperCase();

        for (const chord of _activeChords) {
            if (chord.key.toUpperCase() === normalized) {
                dispatchChord(chord);
                return true;
            }
        }

        return false;
    }

    /// Execute a chord command via shell. Internal — callers should use dispatchChord().
    /// SECURITY: Commands come from user-controlled chords.json.
    /// This file is trusted at the same level as ~/.bashrc —
    /// no sanitization is performed; shell expansion is intentional.
    function _executeCommand(command: string): void {
        if (commandRunner.running) {
            console.warn("[KeyChords] Previous command still running, skipping:", command);
            return;
        }
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
                root.chordGroups = validateGroups(expandWorkspaceGroups(parsed));
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
    /// Keys whose value is not an object (e.g., string comment keys starting with "_") are
    /// silently ignored. Each chord must have a single-character `key`, a non-empty `label`,
    /// and either a non-empty `command` (shell execution) or `group` (sub-group navigation).
    /// If both are present, `group` takes precedence at dispatch time.
    function validateGroups(parsed: var): var {
        const result = {};

        for (const [name, group] of Object.entries(parsed)) {
            if (!group || typeof group !== "object") continue;
            if (!Array.isArray(group.chords)) continue;

            const validChords = group.chords.filter(c =>
                c && typeof c.key === "string" && c.key.length === 1 &&
                typeof c.label === "string" && c.label.length > 0 &&
                (
                    (typeof c.command === "string" && c.command.length > 0) ||
                    (typeof c.group === "string" && c.group.length > 0)
                )
            );

            if (validChords.length > 0) {
                validChords.sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true, sensitivity: "base" }));
                result[name] = {
                    title: typeof group.title === "string" ? group.title : name,
                    chords: validChords
                };
            }
        }

        // Warn about dangling sub-group references (catches typos at load time)
        for (const [name, group] of Object.entries(result)) {
            for (const chord of group.chords) {
                if (chord.group && !result[chord.group])
                    console.warn("[KeyChords] Chord in", name, "references unknown group:", chord.group);
            }
        }

        return result;
    }

    /// Expand "workspace list" groups into concrete chords from a single shared
    /// source, so the workspace set is defined ONCE instead of copy-pasted into
    /// every menu (switch / send / move). A group opts in by declaring an
    /// `expand` object instead of an inline `chords` array; it is generated from
    /// the top-level `_workspaces` array. Groups without `expand` pass through
    /// untouched (and `_workspaces` itself is dropped later by validateGroups,
    /// since it has no `chords`).
    ///
    /// Each `_workspaces` entry is {key, label, ws}, plus an optional `special`
    /// string (the bare special-workspace name; "" for the default special) that
    /// marks the entry as a special workspace. Each `expand` supplies a `command`
    /// template and, optionally, a `specialCommand` used for special entries; in
    /// both, `{ws}` and `{special}` are substituted. Example:
    ///   "_workspaces": [ { "key": "S", "label": "symmetria", "ws": "name:symmetria" } ],
    ///   "workspace": { "title": "Switch", "expand": {
    ///       "command": "switch_workspace.sh {ws}",
    ///       "specialCommand": "hyprctl dispatch togglespecialworkspace {special}" } }
    function expandWorkspaceGroups(parsed: var): var {
        const workspaces = parsed && Array.isArray(parsed._workspaces) ? parsed._workspaces : null;
        if (!workspaces)
            return parsed;

        const out = {};
        for (const [name, group] of Object.entries(parsed)) {
            // Pass through anything that isn't an expand group (incl. _workspaces itself).
            if (!group || typeof group !== "object" || Array.isArray(group) || !group.expand || typeof group.expand !== "object") {
                out[name] = group;
                continue;
            }

            const normalTpl = group.expand.command;
            const specialTpl = group.expand.specialCommand;
            const chords = [];
            for (const ws of workspaces) {
                if (!ws || typeof ws.key !== "string" || typeof ws.label !== "string" || typeof ws.ws !== "string")
                    continue;
                const isSpecial = typeof ws.special === "string";
                const template = (isSpecial && typeof specialTpl === "string") ? specialTpl : normalTpl;
                if (typeof template !== "string")
                    continue;
                const command = template
                    .replace(/\{ws\}/g, ws.ws)
                    .replace(/\{special\}/g, ws.special ?? "");
                chords.push({ key: ws.key, label: ws.label, command });
            }
            out[name] = { title: group.title, chords };
        }
        return out;
    }
}
