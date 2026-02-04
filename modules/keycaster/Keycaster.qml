pragma ComponentBehavior: Bound

import Quickshell

/// Root component for Keycaster key display.
///
/// Unlike HyprWhspr (service-state driven auto-show), Keycaster uses IPC toggle.
/// The Wrapper component handles service activation when visibility changes.
/// This root component is kept for consistency with other modules.
Scope {}
