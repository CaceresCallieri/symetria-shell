pragma Singleton

import qs.config
import qs.utils
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

    // Refresh the clipboard history
    function refresh(): void {
        if (cliphistAvailable) {
            cacheCleanupProcess.running = true;
        }
    }

    // POSIX shell escaping: wrap in single quotes, escape embedded quotes
    // This prevents command injection when passing user data to shell commands
    function shellEscape(str: string): string {
        return "'" + str.replace(/'/g, "'\\''") + "'";
    }

    // Restore an entry to the clipboard
    function restore(id: string): void {
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
        clearProcess.running = true;
    }

    // Decode an image entry to cache for thumbnail display
    function decodeImage(entry: ClipboardEntry): void {
        if (!entry.isImage || entry.imagePath !== "") return;

        const outputPath = `${Paths.clipboardcache}/${entry.id}.png`;

        // Create decode process dynamically
        const process = decodeComponent.createObject(root, {
            entryId: entry.id,
            outputPath: outputPath,
            targetEntry: entry
        });
        process.running = true;
    }

    // Entry component definition
    component ClipboardEntry: QtObject {
        required property string id
        required property string preview
        required property string entryType  // "text" or "image"
        property bool isImage: entryType === "image"
        property string imagePath: ""  // Path to cached image thumbnail (set after decoding)
    }

    // Check for cliphist on startup
    Component.onCompleted: {
        checkProcess.running = true;
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
            if (exitCode !== 0) {
                console.error("Clipboard: cliphist list failed with code", exitCode);
            }
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

                    // Decode image entries to cache for thumbnail display
                    // Deferred to next event loop to:
                    // 1. Prevent blocking UI while entries render
                    // 2. Ensure all entries are fully constructed before decode starts
                    Qt.callLater(() => {
                        for (const entry of root.entries) {
                            if (entry.isImage) {
                                root.decodeImage(entry);
                            }
                        }
                    });

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
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("Clipboard: list stderr:", text.trim());
                }
            }
        }
    }

    // Component factory for creating entries
    Component {
        id: entryComponent
        ClipboardEntry {}
    }

    // Component for async image decoding (no resize - Qt handles via sourceSize)
    Component {
        id: decodeComponent

        Process {
            property string entryId
            property string outputPath
            property ClipboardEntry targetEntry

            // Use parameterized shell arguments to prevent command injection
            command: ["sh", "-c",
                "mkdir -p \"$1\" && cliphist decode \"$2\" > \"$3\"",
                "--",
                Paths.clipboardcache,
                entryId,
                outputPath
            ]

            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0 && targetEntry) {
                    targetEntry.imagePath = outputPath;
                } else if (exitCode !== 0) {
                    console.warn("Clipboard: decode failed for entry", entryId, "code", exitCode);
                }
                destroy();
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    if (text.trim() !== "") {
                        console.warn("Clipboard: decode stderr for", entryId + ":", text.trim());
                    }
                }
            }
        }
    }

    // Restore entry to clipboard using cliphist decode | wl-copy
    Process {
        id: restoreProcess
        property string entryId: ""

        command: ["sh", "-c", `cliphist decode ${root.shellEscape(entryId)} | wl-copy`]

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("Clipboard: restore failed for id", entryId, "code", exitCode);
            }
            if (entryId !== "") {
                root.refresh();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("Clipboard: restore stderr:", text.trim());
                }
            }
        }
    }

    // Delete entry
    Process {
        id: deleteProcess
        property string entryId: ""

        command: ["cliphist", "delete-query", entryId]

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("Clipboard: delete failed for id", entryId, "code", exitCode);
            }
            if (entryId !== "") {
                root.refresh();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("Clipboard: delete stderr:", text.trim());
                }
            }
        }
    }

    // Clear all history
    Process {
        id: clearProcess
        command: ["cliphist", "wipe"]

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("Clipboard: wipe failed with code", exitCode);
            }
            root.refresh();
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("Clipboard: wipe stderr:", text.trim());
                }
            }
        }
    }
}
