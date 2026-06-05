pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Unified power-mode model — the SINGLE source of truth for the ordered set of
// selectable power modes. Both the PowerProfile popout's pill row and the bar's
// click-to-cycle status icon read from `modes`, so they can never drift.
//
// A "mode" is either the virtual Silent overlay (backed by QuietMode: PPD
// power-saver + a kernel freq/boost cap) or one of power-profiles-daemon's
// three real profiles. Silent has no PowerProfile enum of its own, which is
// exactly why a plain profile-cycle can't represent it — hence this layer.
//
// TO ADD A FUTURE MODE: append one entry to `modes` (with its glyph and, if it
// is overlay-like, a backing service). The pill row (built via Repeater) and
// the icon cycle both pick it up automatically — no other file changes.
Singleton {
    id: root

    // Ordered left-to-right, matching the popout row and the cycle direction.
    // `profile: -1` is a sentinel for modes with no PPD profile (Silent); it
    // never matches a real PowerProfile enum, so comparisons stay safe.
    readonly property var modes: [
        ({ silent: true, profile: -1, icon: "bedtime", label: qsTr("Silent") }),
        ({ silent: false, profile: PowerProfile.PowerSaver, icon: "energy_savings_leaf", label: PowerProfile.toString(PowerProfile.PowerSaver) }),
        ({ silent: false, profile: PowerProfile.Balanced, icon: "balance", label: PowerProfile.toString(PowerProfile.Balanced) }),
        ({ silent: false, profile: PowerProfile.Performance, icon: "rocket_launch", label: PowerProfile.toString(PowerProfile.Performance) })
    ]

    // Index of the active mode. Silent wins whenever its overlay is on: it pins
    // PPD to power-saver, so we must NOT report PowerSaver as active in its place.
    // -1 only if PPD reports a profile not in `modes` (shouldn't happen).
    readonly property int activeIndex: QuietMode.enabled ? 0 : root.modes.findIndex(m => !m.silent && m.profile === PowerProfiles.profile)

    readonly property var activeMode: root.modes[root.activeIndex >= 0 ? root.activeIndex : 0]

    function isActive(mode: var): bool {
        return mode.silent ? QuietMode.enabled : (!QuietMode.enabled && PowerProfiles.profile === mode.profile);
    }

    function apply(mode: var): void {
        if (mode.silent) {
            QuietMode.enable();
        } else {
            // Leaving Silent (if it was on): drop the kernel overlay, then select
            // the PPD profile. QuietMode.disable() is profile-neutral, so this
            // assignment is the single writer — no race with the async helper.
            QuietMode.disable();
            PowerProfiles.profile = mode.profile;
        }
    }

    // Advance to the next mode, wrapping around. Drives the bar icon's click.
    function cycle(): void {
        const i = root.activeIndex;
        root.apply(root.modes[(i + 1) % root.modes.length]);
    }
}
