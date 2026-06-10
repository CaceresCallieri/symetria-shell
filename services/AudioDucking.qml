pragma Singleton

import qs.config
import qs.services
import Symmetria
import Quickshell
import QtQuick

/// Temporarily lowers the master sink volume ("ducking") while a microphone
/// is hot, and restores it afterwards. Used by SttService so background
/// audio contaminates transcriptions less.
///
/// Generic by design: callers pass the absolute duck target, no config reads
/// here — reusable by any future feature that records audio.
///
/// Restore is defensive: it skips when the user changed the volume while
/// ducked (their setting wins) or when the sink is muted (Audio.setVolume
/// force-unmutes, which must never happen as a side effect of ducking).
Singleton {
    id: root

    /// Whether a duck is currently applied
    readonly property bool ducked: _ducked

    // Plain properties, NOT readonly — written imperatively by duck()/restore()
    property bool _ducked: false
    property real _savedVolume: -1 // -1 sentinel: nothing to restore
    property real _appliedVolume: -1 // exact value we set, for manual-change detection

    /// Duck the master sink to the ABSOLUTE volume `target` (0..1). If the
    /// current volume is already at or below the target, it is left alone —
    /// ducking must never make audio louder. Idempotent.
    function duck(target: real): void {
        if (_ducked) return;
        _ducked = true;

        // Nothing audible to duck — and setVolume() would unmute the sink.
        if (Audio.muted || Audio.volume <= 0.01) {
            _savedVolume = -1;
            return;
        }

        const clampedTarget = Math.max(0, Math.min(1, target));
        _savedVolume = Audio.volume;
        // Mirror setVolume()'s clamp so the restore comparison is exact
        _appliedVolume = Math.max(0, Math.min(Config.services.maxVolume, Math.min(_savedVolume, clampedTarget)));
        Audio.setVolume(_appliedVolume);
        Logger.log("qml", "stt", "duck | from=" + _savedVolume.toFixed(2) + " to=" + _appliedVolume.toFixed(2));
    }

    /// Restore the pre-duck volume, unless the user changed it meanwhile. Idempotent.
    function restore(): void {
        if (!_ducked) return;
        _ducked = false;
        if (_savedVolume < 0) return;

        const saved = _savedVolume;
        const applied = _appliedVolume;
        _savedVolume = -1;
        _appliedVolume = -1;

        // User silenced output while ducked — restoring would unmute it.
        if (Audio.muted) {
            Logger.log("qml", "stt", "duck restore skipped | sink muted");
            return;
        }
        // User adjusted volume while ducked — their setting wins.
        const epsilon = 0.02;
        if (Math.abs(Audio.volume - applied) > epsilon) {
            Logger.log("qml", "stt", "duck restore skipped | volume changed externally (now=" + Audio.volume.toFixed(2) + " expected=" + applied.toFixed(2) + ")");
            return;
        }
        Audio.setVolume(saved);
        Logger.log("qml", "stt", "duck restore | to=" + saved.toFixed(2));
    }

    // Best-effort restore on QML reload mid-duck. A hard shell crash still
    // leaves the volume low — accepted, one keypress fixes it.
    Component.onDestruction: restore()
}
