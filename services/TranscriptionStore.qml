pragma Singleton
pragma ComponentBehavior: Bound

import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Authoritative store of STT transcriptions, persisted to JSON.
///
/// Unlike the previous marker-based design (which tagged cliphist entries),
/// this store IS the data: STT delivery in "clipboard" mode no longer touches
/// wl-copy / cliphist at all. Instead, the transcribed text is injected via
/// `wtype` directly into the focused window and recorded here for later
/// retrieval via the Transcriptions tab in the clipboard manager or the
/// Alt+V "paste latest" keybind.
///
/// Each entry is `{ id, text, addedAt }`. `id` is generated client-side and
/// used by the UI to identify entries for paste/remove operations via IPC.
Singleton {
    id: root

    /// Array of {id, text, addedAt}. Reassigned (never mutated in place) so
    /// QML bindings depending on `entries.length` re-evaluate.
    property var entries: []

    /// Whether the persisted JSON has been loaded from disk.
    property bool loaded: false

    /// Cap on retained entries — prevents unbounded growth of the JSON file.
    /// Oldest entries beyond this cap are dropped on add().
    readonly property int maxEntries: 200

    // ─────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────

    /// Record a new transcription. Returns the assigned id, or "" on empty input.
    function add(text: string): string {
        if (!text || text.length === 0) {
            console.warn("[TranscriptionStore] add() called with empty text — ignoring");
            return "";
        }
        const id = `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        const entry = { id: id, text: text, addedAt: Date.now() };
        const next = [entry, ...entries];
        if (next.length > maxEntries)
            next.length = maxEntries;
        entries = next;
        _persist();
        return id;
    }

    /// Remove a single entry by id. No-op if id is unknown.
    function remove(id: string): void {
        const filtered = entries.filter(e => e.id !== id);
        if (filtered.length === entries.length) return;
        entries = filtered;
        _persist();
    }

    /// Drop all entries.
    function clear(): void {
        if (entries.length === 0) return;
        entries = [];
        _persist();
    }

    /// Lookup by id. Returns null if no match.
    function getById(id: string): var {
        for (const e of entries)
            if (e.id === id) return e;
        return null;
    }

    /// Paste a transcription via wtype. If `id` is empty/null/undefined, the
    /// most recent entry is used. No-op when the store is empty or the id
    /// doesn't match.
    function paste(id: string): void {
        let entry = null;
        if (id === undefined || id === null || id === "") {
            entry = entries.length > 0 ? entries[0] : null;
        } else {
            entry = getById(id);
        }
        if (!entry) {
            console.warn("[TranscriptionStore] paste(): no matching entry for id =", id);
            return;
        }
        Quickshell.execDetached(["wtype", "--", entry.text]);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────

    function _persist(): void {
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: storage.setText(JSON.stringify(root.entries))
    }

    FileView {
        id: storage

        path: `${Paths.state}/stt/transcriptions.json`
        onLoaded: {
            let data;
            try {
                data = JSON.parse(text());
            } catch (e) {
                console.warn("TranscriptionStore: failed to parse transcriptions.json, starting fresh:", e);
                root.loaded = true;
                return;
            }
            if (Array.isArray(data)) {
                // Legacy marker entries (no `id`) are silently discarded —
                // the previous design only stored {text, addedAt} markers
                // that pointed at cliphist; they have no meaning under the
                // authoritative-store model.
                root.entries = data.filter(e =>
                    e
                    && typeof e.id === "string"
                    && typeof e.text === "string"
                    && typeof e.addedAt === "number"
                );
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                // setText auto-creates the file but not parent dirs; ensure
                // ${Paths.state}/stt exists before the first write.
                Quickshell.execDetached(["mkdir", "-p", `${Paths.state}/stt`]);
                root.loaded = true;
                setText("[]");
            } else {
                // Permission denied / I/O error — degrade to in-memory mode
                // so add() and paste() still work for this session.
                console.warn("TranscriptionStore: failed to load transcriptions.json (err=" + err + "), running in-memory only");
                root.loaded = true;
            }
        }
    }

    IpcHandler {
        target: "transcriptions"

        function paste(id: string): void {
            root.paste(id);
        }

        function pasteLatest(): void {
            root.paste("");
        }

        function remove(id: string): void {
            root.remove(id);
        }

        function clear(): void {
            root.clear();
        }
    }
}
