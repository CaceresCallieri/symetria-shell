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

    BarHarness {
        id: bar
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
        Hypr.calls = [];
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
        wait(10);
        compare(hypr.orderProcess.starts, previousStarts + 1);
        verify(!hypr.orderProcess.running);
    }

    function test_config_reload_refreshes_workspace_order() {
        const previousStarts = hypr.orderProcess.starts;
        hypr.onRawEvent({
            name: "configreloaded"
        });
        tryCompare(hypr.orderProcess, "starts", previousStarts + 1);
        hypr.orderProcess.finish("[]", 0);
    }

    function test_focus_events_do_not_query_workspace_order() {
        const previousStarts = hypr.orderProcess.starts;
        hypr.onRawEvent({
            name: "workspace"
        });
        hypr.onRawEvent({
            name: "workspacev2"
        });
        wait(10);
        compare(hypr.orderProcess.starts, previousStarts);
        verify(!hypr.orderProcess.running);
    }

    function test_refresh_events_data() {
        return ["createworkspace", "createworkspacev2", "destroyworkspace", "destroyworkspacev2", "renameworkspace", "moveworkspace", "moveworkspacev2", "changeworkspaceid"].map(name => ({
                    tag: name,
                    name: name
                }));
    }

    function test_refresh_events(data) {
        const previousStarts = hypr.orderProcess.starts;
        hypr.onRawEvent({
            name: data.name
        });
        tryCompare(hypr.orderProcess, "starts", previousStarts + 1);
        hypr.orderProcess.finish("[]", 0);
    }

    function test_workspace_id_change_updates_numeric_order() {
        const original = [workspace("5", 5, 1), workspace("9", 9, 1)];
        Hyprland.workspaces = {
            values: original
        };
        hypr._workspaceOrder = WorkspaceOrdering.fromSnapshot(original);
        compare(hypr.displayedWorkspaceIds(5), [5, 9]);
        const changed = [original[0], workspace("1", 1, 1)];
        Hyprland.workspaces = {
            values: changed
        };
        hypr.onRawEvent({
            name: "changeworkspaceid"
        });
        tryCompare(hypr.orderProcess, "running", true);
        hypr.orderProcess.finish(JSON.stringify(changed), 0);
        compare(hypr.displayedWorkspaceIds(1), [1, 5]);
    }

    function wheelMonitor(id, special) {
        return {
            activeWorkspace: workspace(id > 0 ? String(id) : "agents", id, 1),
            lastIpcObject: {
                specialWorkspace: {
                    name: special
                }
            }
        };
    }

    function test_wheel_data() {
        return [
            {
                tag: "dynamic-left-named",
                dynamic: true,
                key: -1,
                delta: 120,
                expected: [
                    {
                        action: "focus",
                        selector: "e-1"
                    }
                ]
            },
            {
                tag: "dynamic-right-named",
                dynamic: true,
                key: -1,
                delta: -120,
                expected: [
                    {
                        action: "focus",
                        selector: "e+1"
                    }
                ]
            },
            {
                tag: "fixed-left",
                dynamic: false,
                key: 3,
                delta: 120,
                expected: [
                    {
                        action: "focus",
                        selector: "r-1"
                    }
                ]
            },
            {
                tag: "fixed-right",
                dynamic: false,
                key: 3,
                delta: -120,
                expected: [
                    {
                        action: "focus",
                        selector: "r+1"
                    }
                ]
            },
            {
                tag: "fixed-first-left",
                dynamic: false,
                key: 1,
                delta: 120,
                expected: []
            },
            {
                tag: "fixed-named-left",
                dynamic: false,
                key: -1,
                delta: 120,
                expected: []
            },
            {
                tag: "fixed-named-right",
                dynamic: false,
                key: -1,
                delta: -120,
                expected: [
                    {
                        action: "focus",
                        selector: "r+1"
                    }
                ]
            },
            {
                tag: "dynamic-horizontal",
                dynamic: true,
                key: -1,
                delta: 0,
                expected: []
            },
            {
                tag: "fixed-horizontal",
                dynamic: false,
                key: 3,
                delta: 0,
                expected: []
            },
            {
                tag: "special-horizontal",
                dynamic: true,
                key: -1,
                delta: 0,
                special: "special:music",
                expected: []
            },
            {
                tag: "dynamic-special",
                dynamic: true,
                key: -1,
                delta: 120,
                special: "special:music",
                expected: [
                    {
                        action: "special",
                        name: "special:music"
                    }
                ]
            },
            {
                tag: "fixed-special",
                dynamic: false,
                key: 1,
                delta: -120,
                special: "special:special",
                expected: [
                    {
                        action: "special",
                        name: "special:special"
                    }
                ]
            },
            {
                tag: "disabled",
                dynamic: true,
                key: -1,
                delta: -120,
                disabled: true,
                expected: []
            }
        ];
    }

    function test_wheel(data) {
        Config.bar = {
            scrollActions: {
                workspaces: !data.disabled
            },
            workspaces: {
                showOnlyOccupied: data.dynamic,
                perMonitorWorkspaces: true
            }
        };
        Hypr.screenMonitor = wheelMonitor(data.key, data.special ?? "");
        bar.handleWheel(150, Qt.point(120, data.delta));
        compare(Hypr.calls, data.expected);
    }

    function test_wheel_uses_the_selected_monitor() {
        Hypr.screenMonitor = wheelMonitor(1, "");
        Hypr.focusedMonitor = wheelMonitor(3, "");
        Hypr.activeWsId = 3;
        Config.bar = {
            scrollActions: {
                workspaces: true
            },
            workspaces: {
                showOnlyOccupied: false,
                perMonitorWorkspaces: true
            }
        };
        bar.handleWheel(150, Qt.point(0, 120));
        compare(Hypr.calls, []);
        Config.bar = {
            scrollActions: {
                workspaces: true
            },
            workspaces: {
                showOnlyOccupied: false,
                perMonitorWorkspaces: false
            }
        };
        bar.handleWheel(150, Qt.point(0, 120));
        compare(Hypr.calls, [
            {
                action: "focus",
                selector: "r-1"
            }
        ]);
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
