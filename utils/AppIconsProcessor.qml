pragma Singleton

import Quickshell

/// Shared window grouping and sorting logic for bar/agentbar app icons.
/// Filters swallowed windows, groups by Hyprland tab group, and sorts by screen position.
/// In fullscreen mode, uses cached tiled order to prevent icon shuffling from viewport shifts.
Singleton {
    id: root

    // intentional var: JS Map<int, string[]> — per-workspace address order from last tiled sort
    property var _tiledOrderCache: new Map()

    /// Process toplevels for a workspace and return a structured model.
    /// Returns: Array<{ isGroup: bool, clients: HyprlandToplevel[] }>
    function processClients(workspaceId: int, toplevels: var): var {
        try {
            const clients = toplevels.filter(c => c.workspace?.id === workspaceId);

            // Build set of swallowed window addresses to filter out
            const swallowedAddresses = new Set();
            for (const c of clients) {
                const swallowing = c.lastIpcObject?.swallowing;
                if (typeof swallowing === "string" && swallowing && swallowing !== "0x0")
                    swallowedAddresses.add(swallowing);
            }

            const filtered = clients.filter(c => {
                const addr = c.lastIpcObject?.address;
                return addr && !swallowedAddresses.has(addr);
            });

            // Separate grouped and ungrouped clients
            // Key is sorted addresses joined — stable across any group member order
            const groupMap = new Map();
            const ungrouped = [];
            const ungroupedKeys = [];

            for (const client of filtered) {
                const groupedArr = client.lastIpcObject?.grouped ?? [];
                if (groupedArr.length > 0) {
                    const groupKey = [...groupedArr].sort().join(',');
                    if (!groupMap.has(groupKey))
                        groupMap.set(groupKey, { canonicalOrder: groupedArr, clients: [] });
                    groupMap.get(groupKey).clients.push(client);
                } else {
                    ungrouped.push({ isGroup: false, clients: [client] });
                    ungroupedKeys.push(client.lastIpcObject?.address ?? "");
                }
            }

            // Sort each group's clients by canonical tab order
            const groupEntries = Array.from(groupMap.entries());
            const groups = [];
            const groupKeys = [];
            for (const [groupKey, group] of groupEntries) {
                const { canonicalOrder, clients: groupClients } = group;
                groupClients.sort((a, b) => {
                    const aIdx = canonicalOrder.indexOf(a.lastIpcObject?.address);
                    const bIdx = canonicalOrder.indexOf(b.lastIpcObject?.address);
                    if (aIdx === -1 || bIdx === -1) return 0;
                    return aIdx - bIdx;
                });
                groups.push({ isGroup: true, clients: groupClients });
                groupKeys.push(groupKey);
            }

            // Combine groups and ungrouped entries with a parallel key array.
            // Keys are kept separate to avoid attaching then deleting properties on returned
            // objects — `delete obj.prop` de-optimizes V4 hidden classes (project-standards P0).
            const combined = [...groups, ...ungrouped];
            const combinedKeys = [...groupKeys, ...ungroupedKeys];

            // Detect maximize mode (fullscreen === 1) specifically.
            // Only maximize shifts the viewport in Hyprland's scrolling layout,
            // making position-based sorting unstable. Mode 2 (real fullscreen) hides
            // the bar entirely. Mode 3+ (client-requested, e.g., games) does NOT
            // shift the viewport — other windows keep their tiled positions.
            const hasMaximized = combined.some(entry =>
                entry.clients.some(c => c.lastIpcObject?.fullscreen === 1)
            );

            if (hasMaximized && root._tiledOrderCache.has(workspaceId)) {
                // Maximize mode: sort by cached tiled order; entries not in cache go to end.
                // Stale keys from windows that closed while maximized are harmless — they
                // produce no orderMap entry and are simply absent from combined.
                const cachedOrder = root._tiledOrderCache.get(workspaceId);
                const orderMap = new Map(cachedOrder.map((key, i) => [key, i]));
                // Sort combined and combinedKeys together by zipping indices
                const indices = combined.map((_, i) => i);
                indices.sort((a, b) => {
                    const aIdx = orderMap.get(combinedKeys[a]) ?? Infinity;
                    const bIdx = orderMap.get(combinedKeys[b]) ?? Infinity;
                    return aIdx - bIdx;
                });
                const sortedCombined = indices.map(i => combined[i]);
                return sortedCombined;
            } else {
                // Tiled mode (or first maximize with no prior cache — bootstrap path).
                // The bootstrap case position-sorts correctly; the cache is populated on the
                // preceding tiled event (triggered by the fullscreen event listener).
                //
                // Sort combined and combinedKeys together by zipping indices
                const indices = combined.map((_, i) => i);
                indices.sort((a, b) => {
                    const aClient = combined[a].clients[0];
                    const bClient = combined[b].clients[0];
                    const ax = aClient?.lastIpcObject?.at?.[0] ?? 0;
                    const bx = bClient?.lastIpcObject?.at?.[0] ?? 0;
                    if (ax !== bx) return ax - bx;
                    const ay = aClient?.lastIpcObject?.at?.[1] ?? 0;
                    const by = bClient?.lastIpcObject?.at?.[1] ?? 0;
                    return ay - by;
                });
                const sortedCombined = indices.map(i => combined[i]);
                // Only cache when no window is maximized — position data is reliable.
                // Skip caching if any key is empty (IPC data not yet available for that window).
                if (!hasMaximized && combinedKeys.every(k => k !== ""))
                    root._tiledOrderCache.set(workspaceId, indices.map(i => combinedKeys[i]));
                return sortedCombined;
            }
        } catch (e) {
            console.error("AppIconsProcessor: Failed to process clients:", e);
            return [];
        }
    }

    /// Shallow-compare two cached models to avoid unnecessary Repeater churn.
    /// Returns true if both models represent the same icon layout.
    function modelsEqual(a: var, b: var): bool {
        if (a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            if (a[i].isGroup !== b[i].isGroup) return false;
            const ac = a[i].clients, bc = b[i].clients;
            if (ac.length !== bc.length) return false;
            for (let j = 0; j < ac.length; j++) {
                if (ac[j] !== bc[j]) return false;
            }
        }
        return true;
    }
}
