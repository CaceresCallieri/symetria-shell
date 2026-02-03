pragma Singleton

import qs.config
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Array of { name: string, memoryKib: int, memoryFormatted: { value: real, unit: string } }
    property var topProcesses: []
    property int refCount: 0
    readonly property int processCount: 50 // Show top 50 processes (scrollable)

    Timer {
        running: root.refCount > 0
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: psProcess.running = true
    }

    Process {
        id: psProcess

        // ps aux outputs: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
        // Sort by memory percentage descending, get top N+1 (skip header), extract PID, command, and RSS (KiB)
        command: ["sh", "-c", `ps aux --sort=-%mem | head -${root.processCount + 1} | tail -n +2 | awk '{print $2, $11, $6}'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const processes = [];
                for (const line of text.trim().split("\n")) {
                    if (!line.trim())
                        continue;
                    const parts = line.trim().split(/\s+/, 3);
                    if (parts.length === 3) {
                        const pid = parseInt(parts[0], 10) || 0;
                        // Extract basename from path (e.g., /usr/bin/firefox -> firefox)
                        const fullName = parts[1];
                        const name = fullName.split('/').pop();
                        const memKib = parseInt(parts[2], 10) || 0;
                        processes.push({
                            pid: pid,
                            name: name,
                            memoryKib: memKib,
                            memoryFormatted: SystemUsage.formatKib(memKib)
                        });
                    }
                }
                root.topProcesses = processes;
            }
        }
    }
}
