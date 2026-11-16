import QtQuick
import QtTest
import WorkspaceTest
import "../WorkspaceOrdering.js" as WorkspaceOrdering

TestCase {
    id: testCase
    name: "WorkspaceOrder"

    HyprHarness {
        id: hypr
    }

    function workspace(name, id, windows) {
        return {
            name: name,
            id: id,
            lastIpcObject: {
                windows: windows
            }
        };
    }

    function names(order) {
        return order.map(workspace => workspace.name);
    }

    function displayedNames(active) {
        const ids = hypr.displayedWorkspaceIds(hypr.workspaceKeyForName(active));
        return ids.map(id => Hyprland.workspaces.values.find(workspace => hypr.workspaceKey(workspace) === id)?.name ?? String(id));
    }

    function init() {
        if (hypr.orderProcess.running)
            hypr.orderProcess.finish("[]", 0);
        Hyprland.workspaces = {
            values: []
        };
        WorkspaceCatalog.entries = [];
        Config.bar = {
            workspaces: {
                namedWorkspaceIcons: []
            }
        };
        hypr._workspaceOrder = [];
    }

    function test_transport_startup_and_coalesced_events() {
        compare(hypr.orderProcess.command, ["hyprctl", "-j", "workspaces"]);
        const previousStarts = hypr.orderProcess.starts;
        hypr.onRawEvent({
            name: "createworkspace"
        });
        hypr.onRawEvent({
            name: "createworkspacev2"
        });
        tryCompare(hypr.orderProcess, "starts", previousStarts + 1);
        hypr.orderProcess.finish(JSON.stringify([workspace("files", -1, 1), workspace("agents", -1, 1)]), 0);
        compare(names(hypr._workspaceOrder), ["agents", "files"]);
    }

    function test_event_during_query_gets_a_followup_snapshot() {
        hypr.refreshWorkspaceOrder();
        tryCompare(hypr.orderProcess, "running", true);
        const previousStarts = hypr.orderProcess.starts;
        hypr.onRawEvent({
            name: "destroyworkspacev2"
        });
        wait(10);
        compare(hypr.orderProcess.starts, previousStarts);
        hypr.orderProcess.finish("[]", 0);
        tryCompare(hypr.orderProcess, "starts", previousStarts + 1);
        hypr.orderProcess.finish(JSON.stringify([workspace("browser", -1, 1)]), 0);
        compare(names(hypr._workspaceOrder), ["browser"]);
    }

    function test_invalid_query_keeps_last_good_order() {
        hypr._workspaceOrder = [
            {
                name: "agents",
                id: -1
            }
        ];
        hypr.refreshWorkspaceOrder();
        tryCompare(hypr.orderProcess, "running", true);
        ignoreWarning(/\[Hypr\] ignoring unreadable workspace order:.*/);
        ignoreWarning("[Hypr] workspace order query failed: 1");
        hypr.orderProcess.finish("unreadable", 1);
        compare(names(hypr._workspaceOrder), ["agents"]);
        hypr.onRawEvent({
            name: "renameworkspace"
        });
        tryCompare(hypr.orderProcess, "running", true);
        hypr.orderProcess.finish(JSON.stringify([workspace("browser", -1, 1)]), 0);
        compare(names(hypr._workspaceOrder), ["browser"]);
    }

    function test_compositor_order_overrides_catalog_and_model_order() {
        const snapshot = [workspace("files", -1, 1), workspace("communications", -1, 2), workspace("agents", -1, 1), workspace("browser", -1, 1)];
        WorkspaceCatalog.entries = ["agents", "browser", "communications", "files"].map(name => ({
                    name: name,
                    kind: "named"
                }));
        Hyprland.workspaces = {
            values: snapshot.slice().reverse()
        };
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot(snapshot);
        compare(displayedNames("agents"), ["browser", "agents", "communications", "files"]);
        WorkspaceCatalog.entries = WorkspaceCatalog.entries.slice().reverse();
        compare(displayedNames("agents"), ["browser", "agents", "communications", "files"]);
    }

    function test_mixed_workspaces_and_special_exclusion() {
        const snapshot = [workspace("10", 10, 1), workspace("music", -1, 1), workspace("special:special", -1, 1), workspace("2", 2, 1), workspace("agents", -1, 1), workspace("1", 1, 1)];
        compare(names(WorkspaceOrdering.fromSnapshot(snapshot)), ["agents", "music", "1", "2", "10"]);
        Hyprland.workspaces = {
            values: snapshot
        };
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot(snapshot);
        compare(displayedNames("agents"), ["agents", "music", "1", "2", "10"]);
    }

    function test_create_destroy_and_recreate_named_workspace() {
        const initial = [workspace("files", -1, 1), workspace("agents", -1, 1)];
        compare(names(WorkspaceOrdering.fromSnapshot(initial)), ["agents", "files"]);
        const created = [...initial, workspace("browser", -1, 1)];
        compare(names(WorkspaceOrdering.fromSnapshot(created)), ["browser", "agents", "files"]);
        const destroyed = created.filter(workspace => workspace.name !== "agents");
        compare(names(WorkspaceOrdering.fromSnapshot(destroyed)), ["browser", "files"]);
        compare(names(WorkspaceOrdering.fromSnapshot([...destroyed, initial[1]])), ["agents", "browser", "files"]);
    }

    function test_empty_active_and_declared_slots_stay_visible() {
        const snapshot = [workspace("files", -1, 0), workspace("other", -1, 0), workspace("3", 3, 0), workspace("agents", -1, 0)];
        WorkspaceCatalog.entries = [
            {
                name: "files",
                kind: "named"
            }
        ];
        Hyprland.workspaces = {
            values: snapshot
        };
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot(snapshot);
        compare(displayedNames("agents"), ["agents", "files"]);
        compare(displayedNames("3"), ["files", "3"]);
    }

    function test_pending_snapshot_keeps_new_and_active_slots() {
        Hyprland.workspaces = {
            values: [workspace("agents", -1, 1), workspace("browser", -1, 1)]
        };
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot([workspace("agents", -1, 1)]);
        compare(displayedNames("browser"), ["agents", "browser"]);
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot(Hyprland.workspaces.values);
        compare(displayedNames("browser"), ["browser", "agents"]);
    }

    function test_renamed_numbered_workspace_keeps_numeric_identity() {
        const snapshot = [workspace("renamed", 4, 1), workspace("1", 1, 1)];
        Hyprland.workspaces = {
            values: snapshot
        };
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot(snapshot);
        compare(hypr.displayedWorkspaceIds(4), [1, 4]);
    }

    function test_empty_and_invalid_snapshots() {
        compare(WorkspaceOrdering.fromSnapshot([]), []);
        for (const invalid of [null,
            {},
            [null], [
                {}
            ]]) {
            let threw = false;
            try {
                WorkspaceOrdering.fromSnapshot(invalid);
            } catch (error) {
                threw = true;
            }
            verify(threw);
        }
    }
}
