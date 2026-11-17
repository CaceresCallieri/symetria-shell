.pragma library

// Hyprland 0.57.2's e/m selectors reverse the compositor's creation list for
// named workspaces, then append numbered workspaces in ascending ID order.
// Source: src/state/workspace/Resolver.cpp at tag v0.57.2.
// Read the raw IPC snapshot: Quickshell's model can reorder equal (-1) IDs.
function fromSnapshot(workspaces) {
    if (!Array.isArray(workspaces))
        throw new Error("missing workspace array");

    const named = [];
    const numbered = [];
    for (const workspace of workspaces) {
        if (!workspace || typeof workspace.name !== "string")
            throw new Error("missing workspace name");
        if (workspace.type === "special" || workspace.name.startsWith("special:"))
            continue;
        const identity = { id: workspace.id > 0 ? workspace.id : -1, name: workspace.name };
        if (identity.id > 0)
            numbered.push(identity);
        else
            named.push(identity);
    }
    numbered.sort((a, b) => a.id - b.id);
    return [...named.reverse(), ...numbered];
}
