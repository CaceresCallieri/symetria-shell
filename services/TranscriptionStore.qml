pragma Singleton
pragma ComponentBehavior: Bound

import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Authoritative store of STT transcriptions, persisted to JSON.
///
/// Unlike the previous marker-based design (which tagged cliphist entries),
/// this store IS the data — independent of cliphist. Re-pasting from this
/// store uses `wl-copy` to put the text back on the system clipboard, then
/// scrubs the entry from cliphist via `cliphist delete-query` after a short
/// delay so the clipboard manager's Text tab doesn't get polluted. The
/// Transcriptions tab is unaffected (different store).
///
/// `wtype` was used in an earlier iteration to auto-type the text into the
/// focused window, but it proved unreliable: any focus change mid-type
/// scattered characters across windows. The wl-copy + manual Ctrl+V flow is
/// less magical but bulletproof — the same flow the clipboard manager uses
/// when the user clicks an entry.
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

    /// Texts queued for cliphist delete-query after the next paste fires.
    /// Queued (not stomped) so rapid successive pastes don't lose scrubs.
    /// Cleared atomically when scrubTimer fires.
    property var _pendingScrubs: []

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

    /// Put a transcription on the system clipboard for instant Ctrl+V paste,
    /// and queue a cliphist scrub so the entry doesn't appear in the Text
    /// tab. If `id` is empty/null/undefined, the most recent entry is used.
    /// No-op when the store is empty or the id doesn't match.
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
        Quickshell.execDetached(["wl-copy", entry.text]);
        const next = _pendingScrubs.slice();
        next.push(entry.text);
        _pendingScrubs = next;
        scrubTimer.restart();
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

    /// Delayed cliphist scrub. The wl-paste --watch daemon that backs
    /// cliphist writes captured entries to its db asynchronously (~tens of
    /// ms after the wl-copy change event). Firing delete-query immediately
    /// would race against that write. 300ms is comfortably above the
    /// observed capture latency without keeping the entry visible long
    /// enough for a human to notice in the Text tab. Mirrors the timer in
    /// SttJob.qml — same delay, same reasoning.
    Timer {
        id: scrubTimer
        interval: 300
        onTriggered: {
            for (const text of root._pendingScrubs)
                Quickshell.execDetached(["cliphist", "delete-query", text]);
            root._pendingScrubs = [];
        }
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
