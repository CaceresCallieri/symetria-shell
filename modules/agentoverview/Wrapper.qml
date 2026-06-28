pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Io

/// IPC entry point for the Agent Overview feature.
///
/// Routes `symmetria shell agentoverview {show,hide,toggle,cycleFilter}` to
/// AgentOverviewService. The actual overlay rendering lives in
/// OverviewSurface.qml, mounted separately in shell.qml, which reads its state
/// from the singleton.
Scope {
    id: root

    IpcHandler {
        target: "agentoverview"

        function show(): void {
            AgentOverviewService.show();
        }

        function hide(): void {
            AgentOverviewService.hide();
        }

        function toggle(): void {
            AgentOverviewService.toggle();
        }

        function cycleFilter(): void {
            AgentOverviewService.cycleFilter();
        }
    }
}
