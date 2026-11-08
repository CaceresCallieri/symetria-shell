pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

/// The named workspaces, as the compositor config defines them.
///
/// The Hyprland config keeps the one list of named workspaces (name, key,
/// icon, label, kind) and writes it as JSON on every config load; the
/// reference setup does so from `~/.config/hypr/workspace_catalog.lua`. This
/// service reads that file, so the chord menus (KeyChordsService, with
/// `"_workspaces": "catalog"` in chords.json) and the bar icons (Icons.qml)
/// follow the compositor instead of keeping copies that drift.
///
/// File shape:
///   { "version": 1, "workspaces": [
///       { "name": "music", "key": "M", "label": "music", "icon": "mat:library_music", "kind": "named" },
///       { "name": "special", "key": "S", "label": "scratchpad", "icon": "mat:lightbulb", "kind": "special" } ] }
///
/// No file means no catalog: `available` stays false and every consumer falls
/// back to its own configuration (chords.json `_workspaces` array, the bar's
/// namedWorkspaceIcons / specialWorkspaceIcons).
Singleton {
    id: root

    /// Override with SYMMETRIA_WORKSPACE_CATALOG; the default is where the
    /// reference Hyprland config writes it.
    readonly property string path: Quickshell.env("SYMMETRIA_WORKSPACE_CATALOG") || `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/workspace-catalog.json`

    // intentional var: list of plain JS objects {name, key, label, icon, kind}
    property var entries: []
    readonly property bool available: entries.length > 0

    /// The catalog icon of a workspace, or "" when the catalog has none.
    /// `kind` is "named" or "special"; `name` is the bare name (no `special:`).
    function iconFor(name: string, kind: string): string {
        const lowerName = name.toLowerCase();
        return entries.find(entry => entry.kind === kind && entry.name.toLowerCase() === lowerName)?.icon ?? "";
    }

    /// The catalog in the `_workspaces` entry shape that KeyChordsService
    /// expands: {key, label, ws}, plus `special` (the bare special name, "" for
    /// Hyprland's default special workspace) on special entries.
    function chordWorkspaces(): var {
        return entries.map(entry => {
            if (entry.kind !== "special")
                return {
                    key: entry.key,
                    label: entry.label,
                    ws: `name:${entry.name}`
                };
            return {
                key: entry.key,
                label: entry.label,
                ws: `special:${entry.name}`,
                special: entry.name === "special" ? "" : entry.name
            };
        });
    }

    function _parseEntries(text: string): var {
        const parsed = JSON.parse(text);
        if (!parsed || !Array.isArray(parsed.workspaces))
            throw new Error("missing `workspaces` array");
        return parsed.workspaces.filter(entry => entry && typeof entry.name === "string" && entry.name.length > 0 && typeof entry.key === "string" && entry.key.length === 1).map(entry => ({
                    name: entry.name,
                    key: entry.key,
                    label: typeof entry.label === "string" && entry.label.length > 0 ? entry.label : entry.name,
                    icon: typeof entry.icon === "string" ? entry.icon : "",
                    kind: entry.kind === "special" ? "special" : "named"
                }));
    }

    FileView {
        path: root.path
        watchChanges: true

        onFileChanged: reload()

        onLoaded: {
            // The writer rewrites the file in place, so a read can land mid-write.
            // Keep the last good list then; the completed write triggers another
            // change notification.
            // Hyprland rewrites the file on every config reload; reassign only on
            // a real change so consumers (an open chord menu) are not reset.
            try {
                const parsedEntries = root._parseEntries(text());
                if (JSON.stringify(parsedEntries) !== JSON.stringify(root.entries))
                    root.entries = parsedEntries;
            } catch (error) {
                console.warn(`[WorkspaceCatalog] ignoring unreadable ${root.path}: ${error.message}`);
            }
        }

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.entries = [];
            else
                console.warn(`[WorkspaceCatalog] failed to read ${root.path}: ${FileViewError.toString(error)}`);
        }
    }
}
