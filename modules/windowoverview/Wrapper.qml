pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Io

/// IPC entry point for the Window Overview feature.
///
/// Routes `symmetria shell overview {show,hide,toggle}` to WindowOverviewService.
/// The actual overlay rendering lives in OverviewSurface.qml,
/// which is mounted separately in shell.qml and reads its state from the singleton.
Scope {
    id: root

    IpcHandler {
        target: "overview"

        function show(): void {
            WindowOverviewService.show();
        }

        function hide(): void {
            WindowOverviewService.hide();
        }

        function toggle(): void {
            WindowOverviewService.toggle();
        }
    }
}
