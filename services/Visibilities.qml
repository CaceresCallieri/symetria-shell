pragma Singleton

import Quickshell

Singleton {
    property var screens: new Map()
    property var bars: new Map()
    property var osdOverlays: new Map()
    property var agentBars: new Map()
    property var popouts: new Map()
    // Per-screen Utilities.Wrapper references — named *Panels to avoid confusion
    // with screens.get(monitor).utilities (a boolean visibility flag).
    property var utilitiesPanels: new Map()

    // Reactive counter - increments when screens map changes.
    // Include this in bindings that use screens.get() to force re-evaluation.
    property int screensVersion: 0

    // Reactive counter - increments when bars map changes.
    // Include this in bindings that use bars.get() to force re-evaluation.
    property int barsVersion: 0

    // Reactive counter - increments when agentBars map changes.
    property int agentBarsVersion: 0

    // Reactive counter - increments when popouts map changes.
    // Read this inside bindings on popouts.get() so they re-evaluate on register/unregister.
    property int popoutsVersion: 0

    // Reactive counter - increments when utilitiesPanels map changes.
    property int utilitiesPanelsVersion: 0

    function load(screen: ShellScreen, visibilities: var): void {
        screens.set(Hypr.monitorFor(screen), visibilities);
        screensVersion++;  // Trigger reactive updates
    }

    function getForActive(): PersistentProperties {
        return screens.get(Hypr.focusedMonitor);
    }

    // Reactive getter - use this instead of screens.get() directly.
    //
    // Usage:
    //   readonly property var visibilities: Visibilities.getForMonitor(Hypr.monitorFor(screen))
    //
    // This binding will update when screens map changes (via screensVersion counter).
    // Direct use of screens.get() would NOT update reactively.
    function getForMonitor(monitor: var): var {
        // Reading screensVersion forces re-evaluation when map changes
        void screensVersion;
        return screens.get(monitor);
    }
}
