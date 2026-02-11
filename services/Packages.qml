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
/// Also provides detail fetching via `paru -Si` and `paru -Qi`.
Singleton {
    id: root

    // ===== Search state =====

    /// Parsed search results (list of PackageEntry QtObjects)
    property list<PackageEntry> results: []

    /// Whether a search process is currently running
    property bool searching: false

    /// Whether at least one search has been completed this session
    property bool hasSearched: false

    /// The query that produced the current results
    property string currentQuery: ""

    // ===== Detail state =====

    /// The currently loaded package detail (null when not showing detail)
    property PackageDetail selectedDetail: null

    /// Whether a detail fetch is in progress
    property bool fetchingDetail: false

    /// Error message from the last failed detail fetch
    property string detailError: ""

    // ===== Search functions =====

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

    // ===== Detail functions =====

    /// Fetch detailed package info. Runs `paru -Si` first, then `-Qi` if installed.
    function fetchDetail(name: string, installed: bool): void {
        console.log("[Packages] fetchDetail:", name, "installed:", installed);

        // Kill any running detail fetch
        if (detailSiProcess.running)
            detailSiProcess.running = false;
        if (detailQiProcess.running)
            detailQiProcess.running = false;

        // Clear previous detail
        if (selectedDetail) {
            selectedDetail.destroy();
            selectedDetail = null;
        }

        detailError = "";
        fetchingDetail = true;
        detailSiProcess._packageName = name;
        detailSiProcess._isInstalled = installed;
        detailSiProcess.command = ["paru", "-Si", "--", name];
        detailSiProcess.running = true;
        detailTimeout.restart();
    }

    /// Clear detail state and return to results view
    function clearDetail(): void {
        detailTimeout.stop();
        if (detailSiProcess.running)
            detailSiProcess.running = false;
        if (detailQiProcess.running)
            detailQiProcess.running = false;

        if (selectedDetail) {
            selectedDetail.destroy();
            selectedDetail = null;
        }
        fetchingDetail = false;
        detailError = "";
    }

    /// Navigate from detail view back to search with a dependency name
    function searchFromDetail(name: string): void {
        clearDetail();
        currentQuery = name;
        root.searchFromDetailRequested(name);
    }

    /// Open a URL in the default browser
    function openUrl(url: string): void {
        Quickshell.execDetached(["xdg-open", url]);
    }

    /// Signal emitted when searchFromDetail is called, so the UI can update the text field
    signal searchFromDetailRequested(name: string)

    // ===== Parse helpers =====

    /// Parse paru's `Key : Value` output format into a JS object.
    /// Handles multi-line continuation (lines starting with spaces).
    function parsePackageInfo(text: string): var {
        const result = {};
        let currentKey = null;
        const lines = text.split("\n");
        for (const line of lines) {
            const match = line.match(/^([A-Za-z][A-Za-z0-9 ]*?)\s*:\s*(.*)$/);
            if (match) {
                currentKey = match[1].trim();
                result[currentKey] = match[2].trim();
            } else if (currentKey && line.startsWith("  ")) {
                result[currentKey] += "\n" + line.trim();
            }
        }
        return result;
    }

    /// Parse optional dependencies string into structured array.
    /// Input format: "pkg1: description1\npkg2: description2 [installed]"
    function parseOptionalDeps(raw: string): var {
        if (!raw || raw === "None")
            return [];

        const deps = [];
        for (const line of raw.split("\n")) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            const isInstalled = trimmed.endsWith("[installed]");
            const clean = isInstalled ? trimmed.replace(/\s*\[installed\]\s*$/, "") : trimmed;
            const colonIdx = clean.indexOf(":");
            if (colonIdx !== -1) {
                deps.push({
                    name: clean.substring(0, colonIdx).trim(),
                    description: clean.substring(colonIdx + 1).trim(),
                    installed: isInstalled
                });
            } else {
                deps.push({
                    name: clean.trim(),
                    description: "",
                    installed: isInstalled
                });
            }
        }
        return deps;
    }

    /// Split a space-separated dependency list, filtering out "None"
    function splitDepList(raw: string): var {
        if (!raw || raw === "None")
            return [];
        return raw.split(/\s+/).filter(d => d.length > 0);
    }

    // ===== Search process =====

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

    // ===== Detail processes =====

    /// First step: fetch sync info (works for repo + AUR packages)
    Process {
        id: detailSiProcess

        property string _packageName: ""
        property bool _isInstalled: false

        Component.onDestruction: if (running) running = false

        stdout: StdioCollector {
            onStreamFinished: {
                const info = root.parsePackageInfo(text);
                if (!info["Name"]) {
                    root.detailError = qsTr("Failed to parse package info");
                    root.fetchingDetail = false;
                    return;
                }

                const isAur = (info["Repository"] ?? "").toLowerCase() === "aur";

                const detail = detailComponent.createObject(root, {
                    repo: info["Repository"] ?? "",
                    name: info["Name"] ?? "",
                    version: info["Version"] ?? "",
                    description: info["Description"] ?? "",
                    architecture: info["Architecture"] ?? "",
                    url: info["URL"] ?? "",
                    licenses: info["Licenses"] ?? "",
                    provides: info["Provides"] ?? "None",
                    groups: info["Groups"] ?? "None",
                    dependsOn: info["Depends On"] ?? "None",
                    optionalDeps: info["Optional Deps"] ?? "None",
                    makeDepends: info["Make Deps"] ?? "None",
                    conflictsWith: info["Conflicts With"] ?? "None",
                    replaces: info["Replaces"] ?? "None",
                    downloadSize: info["Download Size"] ?? "",
                    installedSize: info["Installed Size"] ?? "",
                    packager: info["Packager"] ?? "",
                    buildDate: info["Build Date"] ?? "",
                    installed: detailSiProcess._isInstalled,
                    isAur: isAur,
                    // AUR-specific fields
                    aurUrl: info["AUR URL"] ?? "",
                    maintainer: info["Maintainer"] ?? "",
                    outOfDate: info["Out-of-date"] ?? "",
                    firstSubmitted: info["First Submitted"] ?? "",
                    lastModified: info["Last Modified"] ?? "",
                    votes: parseInt(info["Votes"] ?? "-1") || -1,
                    popularity: parseFloat(info["Popularity"] ?? "-1") || -1
                });

                root.selectedDetail = detail;

                // Chain -Qi for installed packages to get requiredBy/optionalFor
                if (detailSiProcess._isInstalled) {
                    detailQiProcess.command = ["paru", "-Qi", "--", detailSiProcess._packageName];
                    detailQiProcess.running = true;
                } else {
                    root.fetchingDetail = false;
                    detailTimeout.stop();
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    ProcessUtils.logStderr("Packages", "detail-si", text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !detailQiProcess.running) {
                root.detailError = qsTr("Package not found");
                root.fetchingDetail = false;
                detailTimeout.stop();
            }
        }
    }

    /// Second step: fetch installed-only info (Required By, Optional For, etc.)
    Process {
        id: detailQiProcess

        Component.onDestruction: if (running) running = false

        stdout: StdioCollector {
            onStreamFinished: {
                const info = root.parsePackageInfo(text);
                if (root.selectedDetail) {
                    root.selectedDetail.requiredBy = info["Required By"] ?? "None";
                    root.selectedDetail.optionalFor = info["Optional For"] ?? "None";
                    root.selectedDetail.installDate = info["Install Date"] ?? "";
                    root.selectedDetail.installReason = info["Install Reason"] ?? "";
                }
                root.fetchingDetail = false;
                detailTimeout.stop();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    ProcessUtils.logStderr("Packages", "detail-qi", text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            // -Qi failure is non-fatal; we still have -Si data
            if (exitCode !== 0) {
                console.warn("[Packages] paru -Qi failed (code", exitCode, "), continuing with -Si data only");
                root.fetchingDetail = false;
                detailTimeout.stop();
            }
        }
    }

    Timer {
        id: detailTimeout
        interval: 10000
        onTriggered: {
            console.warn("[Packages] Detail fetch timed out after 10s");
            if (detailSiProcess.running) detailSiProcess.running = false;
            if (detailQiProcess.running) detailQiProcess.running = false;
            root.detailError = qsTr("Request timed out");
            root.fetchingDetail = false;
        }
    }

    // ===== Data models =====

    /// Data model for a single package search result
    component PackageEntry: QtObject {
        property string repo: ""
        property string name: ""
        property string version: ""
        property string description: ""
        property bool installed: false
        property bool isAur: false
        property int votes: -1
    }

    /// Detailed package info from `paru -Si` (and optionally `-Qi`)
    component PackageDetail: QtObject {
        // Core info (from paru -Si, always available)
        property string repo: ""
        property string name: ""
        property string version: ""
        property string description: ""
        property string architecture: ""
        property string url: ""
        property string licenses: ""
        property string provides: "None"
        property string groups: "None"
        property string dependsOn: "None"
        property string optionalDeps: "None"
        property string makeDepends: "None"
        property string conflictsWith: "None"
        property string replaces: "None"
        property string downloadSize: ""
        property string installedSize: ""
        property string packager: ""
        property string buildDate: ""
        property bool installed: false
        property bool isAur: false
        // AUR-specific (from paru -Si on AUR packages)
        property string aurUrl: ""
        property string maintainer: ""
        property string outOfDate: ""
        property string firstSubmitted: ""
        property string lastModified: ""
        property int votes: -1
        property real popularity: -1
        // From paru -Qi only (installed packages)
        property string requiredBy: "None"
        property string optionalFor: "None"
        property string installDate: ""
        property string installReason: ""

        // Cached parsed lists — computed once when raw strings change,
        // avoiding repeated parsing in QML binding evaluations
        readonly property var depsList: root.splitDepList(dependsOn)
        readonly property var optDepsList: root.parseOptionalDeps(optionalDeps)
        readonly property var makeDependsList: root.splitDepList(makeDepends)
        readonly property var requiredByList: root.splitDepList(requiredBy)
        readonly property var optionalForList: root.splitDepList(optionalFor)
    }

    Component {
        id: entryComponent

        PackageEntry {}
    }

    Component {
        id: detailComponent

        PackageDetail {}
    }
}
