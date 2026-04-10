pragma Singleton

import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // List of clipboard entries
    property list<ClipboardEntry> entries: []

    // Whether we have loaded data
    property bool hasData: false

    // Whether cliphist is available
    property bool cliphistAvailable: true

    // Reference counting for lazy initialization
    property int refCount: 0

    // Maximum entries to display (configurable)
    readonly property int maxShown: Config.clipboard.maxShown

    // Preview length for text entries
    readonly property int previewLength: Config.clipboard.previewLength

    // Script path for image decoding (handles truncated PNG repair via PIL)
    readonly property string _decodeScript: Qt.resolvedUrl("../scripts/cliphist-decode-image.sh").toString().replace(/^file:\/\//, "")

    // Refresh the clipboard history
    function refresh(): void {
        if (cliphistAvailable) {
            // Clear the grid model immediately so delegates don't reference
            // files that are about to be deleted by cache cleanup.
            decodedImageModel.clear();

            // Abort any pending decode queue from a previous refresh
            _decodeQueue = [];
            _refreshGeneration++;

            console.debug(`[Clipboard] refresh: active=${_activeDecodes}`);
            cacheCleanupProcess.running = true;
        }
    }

    // Suppress clipboard toast when we initiate the copy ourselves
    property bool _suppressClipboardToast: false

    // Restore an entry to the clipboard
    function restore(id: string): void {
        _suppressClipboardToast = true;
        restoreProcess.entryId = id;
        restoreProcess.running = true;
    }

    // Delete a specific entry
    function remove(id: string): void {
        deleteProcess.entryId = id;
        deleteProcess.running = true;
    }

    // Clear all clipboard history
    function clear(): void {
        _suppressClipboardToast = true;
        clearProcess.running = true;
    }

    // --- Sequential decode queue to avoid thundering herd on cliphist's bolt DB ---
    // With 152 images, spawning all at once causes concurrent reads that corrupt output.
    // 6 balances startup speed vs bolt DB I/O; safe since we only decode ~12-18 images
    // (maxImagesDisplayed + backfills for truncated entries), not the full 150+ pool.
    readonly property int _maxConcurrentDecodes: 6
    property int _activeDecodes: 0
    property int _refreshGeneration: 0
    property var _decodeQueue: []
    // Reserve pool: remaining images not yet queued, used to backfill when
    // truncated images are skipped (so the grid fills to maxImagesDisplayed).
    property var _imagePool: []

    // Public model for the image grid. Pre-populated with slots in correct
    // order at parse time; delegates bind to entry.imagePath and auto-update
    // when decodes complete. No model mutations during decoding (order-safe).
    property alias decodedImageEntries: decodedImageModel
    ListModel { id: decodedImageModel }

    function _enqueueDecode(entry: ClipboardEntry): void {
        if (!entry.isImage || entry.imagePath !== "") return;
        _decodeQueue.push(entry);
    }

    function _processDecodeQueue(): void {
        while (_activeDecodes < _maxConcurrentDecodes && _decodeQueue.length > 0) {
            _startDecode(_decodeQueue.shift());
        }
    }

    // Linear scan is fine: model is bounded by maxImagesDisplayed (default 12).
    function _findModelIndex(entryId: string): int {
        for (let i = 0; i < decodedImageModel.count; i++) {
            if (decodedImageModel.get(i).entryId === entryId)
                return i;
        }
        return -1;
    }

    // Called when a decode is skipped (truncated) or fails. Removes the
    // entry's slot from the model and tries to backfill from the reserve pool.
    function _handleSkippedDecode(entryId: string): void {
        const modelIdx = _findModelIndex(entryId);
        if (modelIdx >= 0)
            decodedImageModel.remove(modelIdx);

        // Pull next valid entry from the reserve pool and append at end
        // (pool entries are always older, so tail position is correct).
        while (_imagePool.length > 0) {
            const next = _imagePool.shift();
            if (next && next.isImage && next.imagePath === "") {
                decodedImageModel.append({"entry": next, "entryId": next.id});
                _enqueueDecode(next);
                return;
            }
        }
    }

    function _startDecode(entry: ClipboardEntry): void {
        const outputPath = `${Paths.clipboardcache}/${entry.id}.png`;
        const process = decodeComponent.createObject(root, {
            entryId: entry.id,
            outputPath: outputPath,
            generation: root._refreshGeneration
        });
        _activeDecodes++;
        process.running = true;
    }

    // Entry component definition
    component ClipboardEntry: QtObject {
        required property string id
        required property string preview
        required property string entryType  // "text" or "image"
        property bool isImage: entryType === "image"
        property string imagePath: ""  // Path to cached image thumbnail (set after decoding)
        property bool skipped: false   // True if image was truncated and skipped during decode
    }

    // Check for cliphist on startup; clean up any orphaned toast thumbnails from prior sessions
    Component.onCompleted: {
        checkProcess.running = true;
        toastThumbCleanupProcess.running = true;
    }

    // Refresh when service becomes active (drawer opens)
    onRefCountChanged: {
        if (refCount > 0) {
            refresh();
        }
    }

    // Check if cliphist is installed
    Process {
        id: checkProcess
        command: ["which", "cliphist"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("Clipboard: cliphist not installed. Install with: paru -S cliphist");
                root.cliphistAvailable = false;
                root.hasData = true;
            }
        }
    }

    // Clear image cache before refreshing (prevents unbounded disk growth)
    Process {
        id: cacheCleanupProcess
        command: ["rm", "-rf", Paths.clipboardcache]
        onExited: listProcess.running = true
    }

    // List clipboard entries
    Process {
        id: listProcess
        command: ["cliphist", "list"]

        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("Clipboard", "list", exitCode, "");
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const newEntries = [];

                try {
                    if (!text || text.trim() === "") {
                        // Empty clipboard - clean up old entries
                        for (const entry of root.entries) {
                            entry.destroy();
                        }
                        root.entries = [];
                        root.hasData = true;
                        return;
                    }

                    const lines = text.trim().split("\n");
                    const maxEntries = Math.min(lines.length, root.maxShown);

                    for (let i = 0; i < maxEntries; i++) {
                        const line = lines[i];
                        // cliphist format: <id>\t<preview>
                        const tabIndex = line.indexOf("\t");
                        if (tabIndex === -1) continue;

                        const id = line.substring(0, tabIndex);
                        let preview = line.substring(tabIndex + 1);

                        // Detect image entries (cliphist shows binary data indicator)
                        const isImage = preview.startsWith("[[ binary data");

                        // Truncate long text previews
                        if (!isImage && preview.length > root.previewLength) {
                            preview = preview.substring(0, root.previewLength) + "…";
                        }

                        const entry = entryComponent.createObject(root, {
                            id: id,
                            preview: isImage ? "Image" : preview,
                            entryType: isImage ? "image" : "text"
                        });
                        newEntries.push(entry);
                    }

                    // Only destroy old entries after successful parse
                    for (const entry of root.entries) {
                        entry.destroy();
                    }
                    root.entries = newEntries;
                    root.hasData = true;

                    // Pre-populate the image model with slots in newest-first order.
                    // Delegates bind to entry.imagePath and show loading placeholders
                    // until decodes set imagePath (no model mutations during decoding).
                    const allImages = newEntries.filter(e => e.isImage);
                    const maxDisplay = Config.clipboard.maxImagesDisplayed;
                    const imagesToDecode = allImages.slice(0, maxDisplay);
                    console.debug(`[Clipboard] ${newEntries.length} entries parsed, ${allImages.length} images total, decoding first ${imagesToDecode.length} (max concurrent: ${root._maxConcurrentDecodes})`);

                    root._decodeQueue = [];
                    root._imagePool = allImages.slice(maxDisplay);

                    // Pre-populate model — order is locked here, before any I/O.
                    // Store entryId as a plain string role for reliable lookup
                    // (ListModel.get() may not preserve QML object references).
                    for (const entry of imagesToDecode) {
                        decodedImageModel.append({"entry": entry, "entryId": entry.id});
                    }

                    // Start concurrent decodes (completions just set imagePath)
                    for (const entry of imagesToDecode) {
                        root._enqueueDecode(entry);
                    }
                    root._processDecodeQueue();

                } catch (e) {
                    // Clean up any partially created new entries on failure
                    for (const entry of newEntries) {
                        entry.destroy();
                    }
                    console.error("Clipboard: Failed to parse history:", e);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("Clipboard", "list", text)
        }
    }

    // Component factory for creating entries
    Component {
        id: entryComponent
        ClipboardEntry {}
    }

    // Component for async image decoding with truncated PNG detection.
    // Exit codes: 0 = success, 1 = failure, 2 = truncated (skipped).
    Component {
        id: decodeComponent

        Process {
            id: decodeProcess

            property string entryId
            property string outputPath
            property string decodedSize: ""
            property int generation: 0

            // Script handles: cliphist decode → PIL validate/resize → atomic rename
            // Outputs file size to stdout on success, exits 2 for truncated images.
            command: [root._decodeScript, entryId, outputPath]

            stdout: StdioCollector {
                onStreamFinished: decodeProcess.decodedSize = text.trim()
            }

            onExited: (exitCode, exitStatus) => {
                // Counter is cross-generation: stale decodes still decrement it,
                // which may temporarily throttle the new generation's queue pump.
                root._activeDecodes--;
                if (generation !== root._refreshGeneration) {
                    destroy();
                    return;
                }
                if (exitCode === 0) {
                    // Just set imagePath — the delegate is already bound to it
                    // and will switch from loading placeholder to thumbnail.
                    const entry = root.entries.find(e => e.id === entryId);
                    if (entry) {
                        entry.imagePath = outputPath;
                        console.debug(`[Clipboard] decode ${entryId}: OK size=${decodedSize}B`);
                    }
                } else if (exitCode === 2) {
                    const skippedEntry = root.entries.find(e => e.id === entryId);
                    if (skippedEntry) skippedEntry.skipped = true;
                    console.debug(`[Clipboard] decode ${entryId}: skipped (truncated)`);
                    root._handleSkippedDecode(entryId);
                } else {
                    console.warn(`[Clipboard] decode ${entryId}: FAILED exit=${exitCode}`);
                    root._handleSkippedDecode(entryId);
                }
                root._processDecodeQueue();
                destroy();
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    if (text.trim())
                        console.warn(`[Clipboard] decode ${entryId} stderr: ${text.trim()}`);
                }
            }
        }
    }

    // Restore entry to clipboard using cliphist decode | wl-copy
    Process {
        id: restoreProcess
        property string entryId: ""

        command: ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "--", entryId]

        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("Clipboard", "restore", exitCode, "");
            suppressClearTimer.restart();
            if (exitCode === 0) {
                root.refresh();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("Clipboard", "restore", text)
        }
    }

    // Delete entry
    Process {
        id: deleteProcess
        property string entryId: ""

        command: ["cliphist", "delete-query", entryId]

        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("Clipboard", "delete", exitCode, "");
            if (exitCode === 0) {
                root.refresh();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("Clipboard", "delete", text)
        }
    }

    // Clear all history
    Process {
        id: clearProcess
        command: ["cliphist", "wipe"]

        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("Clipboard", "wipe", exitCode, "");
            suppressClearTimer.restart();
            root.refresh();
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("Clipboard", "wipe", text)
        }
    }

    // Clean up orphaned toast thumbnails left from previous sessions (e.g., shell crash)
    Process {
        id: toastThumbCleanupProcess
        command: ["rm", "-rf", Paths.toastimagecache]
    }

    // --- Clipboard change watcher ---
    // Fires a toast notification on every external clipboard copy.

    readonly property string _thumbScript: Qt.resolvedUrl("../scripts/clipboard-toast-thumb.sh").toString().replace(/^file:\/\//, "")

    // Suppression timer: clears the flag after self-initiated copies (restore/clear)
    Timer {
        id: suppressClearTimer
        interval: 300
        onTriggered: root._suppressClipboardToast = false
    }

    // Leading-edge throttle: first clipboard event fires immediately,
    // subsequent events within 500ms are dropped to avoid toast spam
    // (e.g., rapid terminal selection changes).
    property int _lastToastTime: 0

    // Persistent watcher: outputs primary MIME type on each clipboard change
    Process {
        id: clipboardWatcher

        // wl-paste is independent of cliphist; wl-clipboard is a hard prerequisite (see docs/module-setup.md)
        running: true
        // Classify clipboard by scanning all MIME types: prefer image/* > text/* > first available.
        // Apps like Chromium list internal types first (e.g., chromium/x-internal-source-rfh-token),
        // so head -1 alone would misclassify image/text copies as "other".
        command: ["sh", "-c", `wl-paste --watch sh -c '
            types=$(wl-paste --list-types 2>/dev/null)
            img=$(echo "$types" | grep "^image/" | head -1)
            if [ -n "$img" ]; then echo "$img"; exit; fi
            txt=$(echo "$types" | grep "^text/" | head -1)
            if [ -n "$txt" ]; then echo "$txt"; exit; fi
            echo "$types" | head -1
        '`]

        stdout: SplitParser {
            onRead: data => {
                const mime = data.trim();
                if (!mime || root._suppressClipboardToast || !Config.utilities.toasts.clipboardCopied)
                    return;

                // Leading-edge throttle
                const now = Date.now();
                if (now - root._lastToastTime < 500)
                    return;
                root._lastToastTime = now;

                if (mime.startsWith("text/")) {
                    if (!textPreviewProcess.running)
                        textPreviewProcess.running = true;
                } else if (mime.startsWith("image/")) {
                    if (!imageThumbProcess.running) {
                        imageThumbProcess.mimeType = mime;
                        imageThumbProcess.thumbPath = `${Paths.toastimagecache}/${Date.now()}.png`;
                        imageThumbProcess.running = true;
                    }
                } else {
                    Toaster.toast(qsTr("Copied to clipboard"), mime, "content_copy");
                }
            }
        }

        onExited: watcherRestartTimer.start()
    }

    Timer {
        id: watcherRestartTimer
        interval: 2000
        onTriggered: clipboardWatcher.running = true
    }

    // One-shot: fetch text preview for clipboard toast
    Process {
        id: textPreviewProcess

        command: ["sh", "-c", "wl-paste -n 2>/dev/null | head -c 200"]

        stdout: StdioCollector {
            onStreamFinished: {
                const preview = text.trim().replace(/\n/g, " ");
                if (preview)
                    Toaster.toast(qsTr("Copied to clipboard"), preview, "content_copy");
                else
                    Toaster.toast(qsTr("Copied to clipboard"), qsTr("Text content"), "content_copy");
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn(`[Clipboard] text preview stderr: ${text.trim()}`);
            }
        }
    }

    // One-shot: generate image thumbnail for clipboard toast
    Process {
        id: imageThumbProcess

        property string mimeType: ""
        property string thumbPath: ""

        command: [root._thumbScript, mimeType, thumbPath]

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Toaster.toast(qsTr("Image copied"), mimeType, "image", Toast.Info, 5000, thumbPath);
            } else {
                Toaster.toast(qsTr("Image copied"), mimeType, "image");
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn(`[Clipboard] thumb stderr: ${text.trim()}`);
            }
        }
    }
}
