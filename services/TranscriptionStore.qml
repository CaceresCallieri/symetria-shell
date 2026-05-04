pragma Singleton
pragma ComponentBehavior: Bound

import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Persistent store of STT transcription markers.
///
/// Tags STT-delivered text so the clipboard manager can route it to a separate
/// "Transcriptions" tab instead of the regular "Text" tab. cliphist remains the
/// single source of truth for the actual entries — this store only holds enough
/// information (the truncated preview key) to identify which cliphist entries
/// originated from STT.
///
/// Lookup uses the same truncation length cliphist uses for previews
/// (Config.clipboard.previewLength), so a stored key matches an entry's
/// `preview` field directly. has() is O(1) via _lookupSet.
Singleton {
    id: root

    // Array of {text, addedAt}. Reassigned (never mutated in place) so QML
    // bindings depending on `entries.length` re-evaluate.
    property var entries: []

    // Set of full transcribed texts. Membership uses prefix-match in has()
    // because cliphist truncates differently than Symmetria, so an exact
    // key cannot reliably match Symmetria's `entry.preview`.
    property var _lookupSet: new Set()

    // Whether the persisted JSON has been loaded from disk.
    property bool loaded: false

    // ─────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────

    /// Tag `text` as a transcription. Called by SttJob after wl-copy succeeds.
    function add(text: string): void {
        if (!text || text.length === 0) {
            console.warn("[TranscriptionStore] add() called with empty text — ignoring");
            return;
        }
        // Skip duplicates — cliphist itself dedupes by content.
        if (_lookupSet.has(text))
            return;
        entries = [...entries, { text: text, addedAt: Date.now() }];
        _rebuildLookup();
        _persist();
    }

    /// Whether the given clipboard `preview` corresponds to a stored
    /// transcription. Uses prefix-match because Symmetria truncates long
    /// previews to `previewLength + "…"` (Clipboard.qml:222-224) and cliphist
    /// itself truncates with its own threshold and ellipsis. Either side may
    /// be the truncated one, so we accept a match when one is a prefix of
    /// the other (with trailing ellipsis stripped).
    function has(preview: string): bool {
        if (!preview) return false;
        const stripped = preview.endsWith("…") ? preview.slice(0, -1) : preview;
        if (stripped.length === 0) return false;
        // Fast path: exact match for short transcriptions where preview === text.
        if (_lookupSet.has(stripped) || _lookupSet.has(preview))
            return true;
        // Fallback: prefix match against stored full texts.
        for (const e of entries) {
            if (e.text.startsWith(stripped) || stripped.startsWith(e.text))
                return true;
        }
        return false;
    }

    /// Drop entries whose stored text no longer corresponds to any preview
    /// in `currentPreviews`. Called lazily when the clipboard drawer opens.
    /// `currentPreviews` is an array of preview strings from Clipboard.entries.
    ///
    /// IMPORTANT: prune is destructive and races with two async pipelines:
    /// (1) cliphist's `wl-paste --watch` capturing wl-copy'd text, and
    /// (2) Clipboard.refresh() rebuilding the entries list.
    /// We guard against both:
    ///   - Bail if Clipboard.entries hasn't populated (would orphan everything).
    ///   - Skip recently-added entries (cliphist may not have captured yet).
    function pruneOrphans(currentPreviews: var): void {
        if (!loaded || entries.length === 0)
            return;
        // Refresh likely hasn't completed — refuse to wipe anything based on
        // an empty cliphist snapshot. This is the primary safeguard against
        // shell-startup races where prune runs before Clipboard.entries fills.
        if (!currentPreviews || currentPreviews.length === 0)
            return;
        // Strip ellipses once for efficient comparison.
        const stripped = [];
        for (let i = 0; i < currentPreviews.length; i++) {
            const p = currentPreviews[i];
            stripped.push(p.endsWith("…") ? p.slice(0, -1) : p);
        }
        // Grace period — cliphist captures wl-copy'd text asynchronously
        // (typically <500ms). Anything added in the last minute is exempt
        // from pruning so STT entries aren't nuked between add() and capture.
        const now = Date.now();
        const graceMs = 60000;
        const kept = entries.filter(e => {
            if (now - (e.addedAt ?? 0) < graceMs) return true;
            return stripped.some(s => e.text.startsWith(s) || s.startsWith(e.text));
        });
        if (kept.length === entries.length)
            return;
        entries = kept;
        _rebuildLookup();
        _persist();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────

    function _rebuildLookup(): void {
        const set = new Set();
        for (const e of entries)
            set.add(e.text);
        _lookupSet = set;
    }

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
            if (Array.isArray(data))
                root.entries = data.filter(e => e && typeof e.text === "string");
            root._rebuildLookup();
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                // mkdir + seed empty file. setText auto-creates the file but
                // not parent dirs, so we ensure ${Paths.state}/stt exists.
                Quickshell.execDetached(["mkdir", "-p", `${Paths.state}/stt`]);
                root.loaded = true;
                setText("[]");
            }
        }
    }
}
