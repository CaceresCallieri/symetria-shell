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

            for (const client of filtered) {
                const groupedArr = client.lastIpcObject?.grouped ?? [];
                if (groupedArr.length > 0) {
                    const groupKey = [...groupedArr].sort().join(',');
                    if (!groupMap.has(groupKey))
                        groupMap.set(groupKey, { canonicalOrder: groupedArr, clients: [], _key: groupKey });
                    groupMap.get(groupKey).clients.push(client);
                } else {
                    ungrouped.push({ isGroup: false, clients: [client], _key: client.lastIpcObject?.address ?? "" });
                }
            }

            // Sort each group's clients by canonical tab order
            const groups = Array.from(groupMap.values()).map(group => {
                const { canonicalOrder, clients: groupClients } = group;
                groupClients.sort((a, b) => {
                    const aIdx = canonicalOrder.indexOf(a.lastIpcObject?.address);
                    const bIdx = canonicalOrder.indexOf(b.lastIpcObject?.address);
                    if (aIdx === -1 || bIdx === -1) return 0;
                    return aIdx - bIdx;
                });
                return { isGroup: true, clients: groupClients, _key: group._key };
            });

            // Combine groups and ungrouped entries, then sort
            const combined = [...groups, ...ungrouped];

            // Detect maximize mode (fullscreen === 1) specifically.
            // Only maximize shifts the viewport in Hyprland's scrolling layout,
            // making position-based sorting unstable. Mode 2 (real fullscreen) hides
            // the bar entirely. Mode 3+ (client-requested, e.g., games) does NOT
            // shift the viewport — other windows keep their tiled positions.
            const hasMaximized = combined.some(entry =>
                entry.clients.some(c => c.lastIpcObject?.fullscreen === 1)
            );

            if (hasMaximized && root._tiledOrderCache.has(workspaceId)) {
                // Maximize mode: sort by cached tiled order; entries not in cache go to end
                const cachedOrder = root._tiledOrderCache.get(workspaceId);
                const orderMap = new Map(cachedOrder.map((key, i) => [key, i]));
                combined.sort((a, b) => {
                    const aIdx = orderMap.get(a._key) ?? Infinity;
                    const bIdx = orderMap.get(b._key) ?? Infinity;
                    return aIdx - bIdx;
                });
            } else {
                // Tiled mode (or maximize with no cache — fallback): sort by screen position
                combined.sort((a, b) => {
                    const aClient = a.clients[0];
                    const bClient = b.clients[0];
                    const ax = aClient?.lastIpcObject?.at?.[0] ?? 0;
                    const bx = bClient?.lastIpcObject?.at?.[0] ?? 0;
                    if (ax !== bx) return ax - bx;
                    const ay = aClient?.lastIpcObject?.at?.[1] ?? 0;
                    const by = bClient?.lastIpcObject?.at?.[1] ?? 0;
                    return ay - by;
                });
                // Only cache when no window is maximized — position data is reliable
                if (!hasMaximized)
                    root._tiledOrderCache.set(workspaceId, combined.map(e => e._key));
            }

            // Strip internal keys before returning
            for (const entry of combined) delete entry._key;

            return combined;
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
