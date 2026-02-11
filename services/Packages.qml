pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Package search service singleton.
///
/// Searches repos + AUR via `paru -Ss` with debounced input from the UI.
/// Results are parsed from paru's two-line-per-package output format.
Singleton {
    id: root

    /// Parsed search results (list of PackageEntry QtObjects)
    property list<PackageEntry> results: []

    /// Whether a search process is currently running
    property bool searching: false

    /// Whether at least one search has been completed this session
    property bool hasSearched: false

    /// The query that produced the current results
    property string currentQuery: ""

    /// Start a new search, killing any in-progress one.
    /// Requires at least 2 characters to avoid overly broad results.
    function search(query: string): void {
        console.log("[Packages] search() called with:", JSON.stringify(query));

        // Kill any running search first
        if (searchProcess.running) {
            console.log("[Packages] Killing previous search process");
            searchProcess.running = false;
        }

        const trimmed = query.trim();
        if (trimmed.length < 2) {
            console.log("[Packages] Query too short (<2 chars), clearing");
            clearResults();
            return;
        }

        currentQuery = trimmed;
        searchProcess.command = ["paru", "-Ss", "--topdown", "--limit", Config.packages.maxResults.toString(), "--", trimmed];
        console.log("[Packages] Starting process:", JSON.stringify(searchProcess.command));
        searchProcess.running = true;
        searchTimeout.restart();
    }

    /// Clear all results and destroy entry objects
    function clearResults(): void {
        searchTimeout.stop();
        for (const entry of results)
            entry.destroy();
        results = [];
        currentQuery = "";
    }

    /// Cancel any running search and clear results
    function cancelSearch(): void {
        if (searchProcess.running)
            searchProcess.running = false;
        clearResults();
    }

    /// Copy `paru -S <name>` to clipboard via wl-copy
    function copyInstallCommand(name: string): void {
        Quickshell.execDetached(["wl-copy", `paru -S ${name}`]);
    }

    Process {
        id: searchProcess

        onRunningChanged: {
            console.log("[Packages] Process onRunningChanged:", running);
            root.searching = running;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("[Packages] stdout onStreamFinished, text length:", text.length);

                const maxResults = Config.packages.maxResults;
                const entries = [];
                const lines = text.trim().split("\n");

                for (let i = 0; i + 1 < lines.length && entries.length < maxResults; i += 2) {
                    const header = lines[i];
                    const desc = lines[i + 1]?.trim() ?? "";

                    const slash = header.indexOf("/");
                    if (slash === -1) continue;

                    const repo = header.substring(0, slash);
                    const rest = header.substring(slash + 1);
                    const parts = rest.split(" ");

                    const name = parts[0];
                    const version = parts[1] ?? "";
                    const installed = /\[Installed/.test(rest);
                    const isAur = repo === "aur";

                    // Parse AUR votes from [+N ~P] format
                    let votes = -1;
                    if (isAur) {
                        const votesMatch = rest.match(/\[\+(\d+)/);
                        if (votesMatch)
                            votes = parseInt(votesMatch[1]);
                    }

                    entries.push(entryComponent.createObject(root, {
                        repo, name, version, description: desc, installed, isAur, votes
                    }));
                }

                // Destroy old results
                for (const old of root.results)
                    old.destroy();

                root.results = entries;
                root.hasSearched = true;
                console.log("[Packages] Parsed", entries.length, "entries. searching:", root.searching, "hasSearched:", root.hasSearched);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    console.log("[Packages] stderr:", text.trim().substring(0, 200));
                    ProcessUtils.logStderr("Packages", "search", text);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            searchTimeout.stop();
            console.log("[Packages] onExited code:", exitCode, "status:", exitStatus, "searching:", root.searching, "results:", root.results.length);
            // Exit code 1 means no results — clear and mark searched
            if (exitCode === 1) {
                for (const old of root.results)
                    old.destroy();
                root.results = [];
                root.hasSearched = true;
            }
        }
    }

    Timer {
        id: searchTimeout
        interval: 15000
        onTriggered: {
            console.log("[Packages] Search timed out after 15s, killing process");
            searchProcess.running = false;
            root.hasSearched = true;
        }
    }

    /// Data model for a single package result
    component PackageEntry: QtObject {
        property string repo: ""
        property string name: ""
        property string version: ""
        property string description: ""
        property bool installed: false
        property bool isAur: false
        property int votes: -1
    }

    Component {
        id: entryComponent

        PackageEntry {}
    }
}
