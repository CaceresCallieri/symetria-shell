pragma Singleton

import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Io
import QtQuick

/// Calculator service singleton managing calculation state and history persistence.
///
/// Uses Qalculator.eval() from the Symmetria C++ plugin for expression evaluation.
/// History is persisted to ~/.local/state/symmetria/calculator.json with debounced saves.
Singleton {
    id: root

    /// Current expression being typed
    property string currentExpression: ""

    /// Result of evaluating current expression (live update as user types)
    property string currentResult: ""

    /// Whether the current result is an error
    property bool hasError: false

    /// Calculation history (newest first)
    property list<HistoryEntry> history: []

    /// Whether history has been loaded from disk
    property bool loaded: false

    /// ============================================================
    /// HISTORY FEATURE - Shelved for future implementation
    /// ============================================================
    /// The history management code below is complete but unused.
    /// UI is commented out in modules/calculator/Content.qml:46-179.
    /// To enable: uncomment UI sections and modify Enter key behavior.
    /// ============================================================

    /// Evaluate an expression and update currentResult
    function evaluate(expr: string): void {
        if (!expr || expr.trim() === "") {
            currentResult = "";
            hasError = false;
            return;
        }

        // Second parameter `false` returns only the result, not "expr = result"
        const result = Qalculator.eval(expr, false);
        currentResult = result;
        // Qalculator errors start with "error:" or "warning:" - use regex to avoid
        // false positives from expressions containing these words mid-string
        hasError = /^error:/i.test(result) || /^warning:/i.test(result);
    }

    /// Add current expression to history (called on Enter)
    function addToHistory(): void {
        if (!currentExpression || currentExpression.trim() === "" || hasError)
            return;

        // Don't add duplicates of the most recent entry
        if (history.length > 0 && history[0].expression === currentExpression)
            return;

        const entry = historyEntryComp.createObject(root, {
            expression: currentExpression,
            result: currentResult,
            timestamp: new Date()
        });

        // Prepend to history (newest first)
        history = [entry, ...history];

        // Trim to max history size
        while (history.length > Config.calculator.maxHistory) {
            const removed = history.pop();
            removed.destroy();
        }

        // Clear current expression after adding
        currentExpression = "";
        currentResult = "";

        // Trigger save
        saveTimer.restart();
    }

    /// Remove a single entry from history by index
    function removeEntry(index: int): void {
        if (index < 0 || index >= history.length)
            return;

        const removed = history[index];
        history = history.filter((_, i) => i !== index);
        removed.destroy();
        saveTimer.restart();
    }

    /// Clear all history
    function clearHistory(): void {
        for (const entry of history)
            entry.destroy();
        history = [];
        saveTimer.restart();
    }

    /// Load a history entry back into the current expression
    function loadFromHistory(index: int): void {
        if (index < 0 || index >= history.length)
            return;

        const entry = history[index];
        currentExpression = entry.expression;
        evaluate(entry.expression);
    }

    /// Copy current result to clipboard via wl-copy
    function copyResult(): void {
        if (currentResult && !hasError)
            Quickshell.execDetached(["wl-copy", currentResult]);
    }

    /// Debounced save timer (1 second delay)
    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: {
            try {
                storage.setText(JSON.stringify(root.history.map(entry => ({
                            expression: entry.expression,
                            result: entry.result,
                            timestamp: entry.timestamp.getTime()
                        }))));
            } catch (e) {
                console.error("[Calculator] Failed to serialize history:", e);
            }
        }
    }

    /// Persistence via FileView
    FileView {
        id: storage

        path: `${Paths.state}/calculator.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const loaded = [];
                for (const item of data) {
                    loaded.push(historyEntryComp.createObject(root, {
                        expression: item.expression,
                        result: item.result,
                        timestamp: new Date(item.timestamp)
                    }));
                }
                root.history = loaded;
            } catch (e) {
                console.warn("[Calculator] Failed to parse history:", e);
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                setText("[]");
            }
        }
    }

    /// History entry component
    component HistoryEntry: QtObject {
        property string expression: ""
        property string result: ""
        property date timestamp: new Date()
    }

    Component {
        id: historyEntryComp

        HistoryEntry {}
    }
}
