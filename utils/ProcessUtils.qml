pragma Singleton

import Quickshell

Singleton {
    id: root

    /// Log a Process error with consistent formatting.
    /// @param name - Service/process identifier (e.g., "Clipboard", "Updates")
    /// @param operation - What was being attempted (e.g., "restore", "list")
    /// @param exitCode - Process exit code
    /// @param stderr - Collected stderr text (can be empty string)
    function logExit(name: string, operation: string, exitCode: int, stderr: string): void {
        if (exitCode === 0)
            return;

        const stderrTrimmed = stderr ? stderr.trim() : "";
        const prefix = `${name}: ${operation}`;

        if (exitCode === 127) {
            console.error(`${prefix}: command not found — is the required tool installed?`);
        } else {
            console.warn(`${prefix}: exited with code ${exitCode}`);
        }

        if (stderrTrimmed !== "") {
            console.warn(`${prefix} stderr: ${stderrTrimmed}`);
        }
    }

    /// Log stderr output from a Process (for use in stderr StdioCollector handlers).
    /// Only logs if stderr is non-empty.
    /// @param name - Service/process identifier
    /// @param operation - What was being attempted
    /// @param stderr - Collected stderr text
    function logStderr(name: string, operation: string, stderr: string): void {
        const trimmed = stderr ? stderr.trim() : "";
        if (trimmed !== "") {
            console.warn(`${name}: ${operation} stderr: ${trimmed}`);
        }
    }
}
