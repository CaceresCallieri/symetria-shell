pragma Singleton

import qs.config
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
            listProcess.running = true;
        }
    }

    // Restore an entry to the clipboard
    // Note: cliphist IDs are numeric database IDs, safe to use directly
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

    // Entry component definition
    component ClipboardEntry: QtObject {
        required property string id
        required property string preview
        required property string entryType  // "text" or "image"
        property bool isImage: entryType === "image"
    }

    // Check for cliphist on startup
    Component.onCompleted: {
        checkProcess.running = true;
    }

    // Refresh when service becomes active (drawer opens)
    onRefCountChanged: {
        if (refCount > 0 && !hasData) {
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

    // Restore entry to clipboard using cliphist decode | wl-copy
    // cliphist IDs are safe numeric values from the database
    Process {
        id: restoreProcess
        property string entryId: ""

        command: ["sh", "-c", `cliphist decode '${entryId}' | wl-copy`]

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
