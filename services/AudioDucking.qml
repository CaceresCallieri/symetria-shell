pragma Singleton

import qs.config
import qs.services
import Symmetria
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

/// Temporarily lowers the output volume ("ducking") while a microphone is
/// hot, and restores it afterwards. Used by SttService so background audio
/// contaminates transcriptions less.
///
/// Generic by design: callers pass the absolute duck target, no config reads
/// here — reusable by any future feature that records audio.
///
/// Tracks SINKS, not "the default sink". A Bluetooth headset swaps its sink
/// node when the mic opens: WirePlumber moves the card from A2DP to HFP, the
/// A2DP sink node disappears and an HFP sink node with the SAME node.name
/// appears with its own volume. Reading `Audio.volume` across that swap
/// compares two devices; restoring at stop-time writes into the HFP node while
/// the A2DP node — the one actually ducked — only returns seconds later, with
/// WirePlumber re-applying the ducked value it stored for that route. The old
/// single-value implementation therefore skipped the restore as "changed
/// externally" and left the headset at volume 0 after every dictation.
///
/// So each sink is keyed by node.name + api.bluez5.profile: every sink that
/// becomes the default while ducked is ducked too, and a sink that is absent
/// at restore-time stays pending until it reappears (bounded window).
///
/// Restore is defensive: it skips a sink whose volume the user changed while
/// ducked (their setting wins) or that is muted. Volumes are written straight
/// to the node — never through Audio.setVolume(), which force-unmutes.
Singleton {
    id: root

    /// Whether a duck is currently applied
    readonly property bool ducked: _ducked

    // Plain properties, NOT readonly — written imperatively by duck()/restore()
    property bool _ducked: false
    property real _duckTarget: 0
    // Sink key → { saved, applied } for every sink ducked by the current duck.
    // A null value marks a sink seen but left alone (muted or already silent).
    property var _duckedSinks: ({})
    // Sink key → { saved, applied, deadline }: restores waiting for their sink
    // to come back (the A2DP sink returns only after the HFP session ends).
    property var _pendingRestores: ({})
    property int _pendingRestoreCount: 0

    // WirePlumber flips an idle headset back to A2DP a few seconds after the
    // capture stops; 20 s covers a slow flip without restoring much later
    // into a session the user has moved on from.
    readonly property int _pendingRestoreWindowMs: 20000
    readonly property real _volumeEpsilon: 0.02

    /// Duck the output to the ABSOLUTE volume `target` (0..1). A sink already
    /// at or below the target is left alone — ducking must never make audio
    /// louder. Idempotent.
    function duck(target: real): void {
        if (_ducked)
            return;
        _ducked = true;
        _duckTarget = Math.max(0, Math.min(1, target));
        _duckedSinks = _adoptPendingRestores();
        _duckSink(Audio.sink);
    }

    /// Restore every ducked sink, unless the user changed it meanwhile. Sinks
    /// that are gone right now are restored when they reappear. Idempotent.
    function restore(): void {
        if (!_ducked)
            return;
        _ducked = false;
        const deadline = Date.now() + _pendingRestoreWindowMs;
        for (const key in _duckedSinks) {
            const entry = _duckedSinks[key];
            if (!entry)
                continue;
            const node = _findSink(key);
            if (node)
                _restoreSink(node, key, entry, false);
            else
                _addPendingRestore(key, entry, deadline);
        }
        _duckedSinks = {};
    }

    /// Identity of one sink in one Bluetooth profile. The A2DP and HFP sinks
    /// of a headset share node.name; api.bluez5.profile tells them apart and
    /// is absent (→ "") on non-Bluetooth sinks. Callers pass usable nodes only.
    function _sinkKey(node: PwNode): string {
        return node.name + "|" + (node.properties["api.bluez5.profile"] ?? "");
    }

    function _isUsable(node: PwNode): bool {
        return !!node && node.ready && !!node.audio;
    }

    function _findSink(key: string): PwNode {
        const sinks = Audio.sinks;
        for (let i = 0; i < sinks.length; i++) {
            if (_isUsable(sinks[i]) && _sinkKey(sinks[i]) === key)
                return sinks[i];
        }
        return null;
    }

    function _duckSink(node: PwNode): void {
        // Not bound yet — the watch timer retries on its next tick.
        if (!_isUsable(node))
            return;
        const key = _sinkKey(node);
        if (key in _duckedSinks)
            return;

        // Nothing audible to duck — and unmuting is never a side effect here.
        // Recorded as null so later ticks skip it: a sink the user unmutes
        // mid-dictation stays loud, same as before sink tracking existed.
        if (node.audio.muted || node.audio.volume <= 0.01) {
            _duckedSinks[key] = null;
            return;
        }

        const saved = node.audio.volume;
        const applied = Math.max(0, Math.min(Config.services.maxVolume, Math.min(saved, _duckTarget)));
        node.audio.volume = applied;
        _duckedSinks[key] = {
            saved: saved,
            applied: applied
        };
        Logger.log("qml", "stt", "duck | sink=" + key + " from=" + saved.toFixed(2) + " to=" + applied.toFixed(2));
    }

    /// Returns true when the entry is settled (restored or deliberately
    /// skipped). `keepWaiting` = the sink may still be settling after its
    /// return (WirePlumber applies the stored route volume asynchronously),
    /// so a mismatch is not yet proof of a user change.
    function _restoreSink(node: PwNode, key: string, entry: var, keepWaiting: bool): bool {
        if (node.audio.muted) {
            Logger.log("qml", "stt", "duck restore skipped | sink=" + key + " muted");
            return true;
        }
        if (Math.abs(node.audio.volume - entry.applied) > _volumeEpsilon) {
            if (keepWaiting)
                return false;
            Logger.log("qml", "stt", "duck restore skipped | sink=" + key + " volume changed externally (now=" + node.audio.volume.toFixed(2) + " expected=" + entry.applied.toFixed(2) + ")");
            return true;
        }
        node.audio.volume = entry.saved;
        Logger.log("qml", "stt", "duck restore | sink=" + key + " to=" + entry.saved.toFixed(2));
        return true;
    }

    /// A new duck that starts while restores are still pending (a dictation
    /// right after another, before the headset flipped back to A2DP) takes
    /// them over: those sinks still hold our duck value, so their ORIGINAL
    /// volume must survive into this duck's restore instead of expiring
    /// mid-dictation or being re-saved as the ducked value. An entry whose
    /// sink is present at a different volume was changed by the user — drop
    /// it and let _duckSink() save the new volume.
    function _adoptPendingRestores(): var {
        const adopted = {};
        for (const key in _pendingRestores) {
            const entry = _pendingRestores[key];
            const node = _findSink(key);
            if (node && Math.abs(node.audio.volume - entry.applied) > _volumeEpsilon) {
                Logger.log("qml", "stt", "duck restore dropped | sink=" + key + " volume changed externally before the next duck (now=" + node.audio.volume.toFixed(2) + " expected=" + entry.applied.toFixed(2) + ")");
                continue;
            }
            adopted[key] = {
                saved: entry.saved,
                applied: entry.applied
            };
        }
        _pendingRestores = {};
        _pendingRestoreCount = 0;
        return adopted;
    }

    function _addPendingRestore(key: string, entry: var, deadline: real): void {
        _pendingRestores[key] = {
            saved: entry.saved,
            applied: entry.applied,
            deadline: deadline
        };
        _pendingRestoreCount = Object.keys(_pendingRestores).length;
        Logger.log("qml", "stt", "duck restore pending | sink=" + key + " (sink absent, waiting for it to return)");
    }

    function _removePendingRestore(key: string): void {
        delete _pendingRestores[key];
        _pendingRestoreCount = Object.keys(_pendingRestores).length;
    }

    function _processPendingRestores(): void {
        const now = Date.now();
        for (const key in _pendingRestores) {
            const entry = _pendingRestores[key];
            const node = _findSink(key);
            const expired = now >= entry.deadline;
            if (node && _restoreSink(node, key, entry, !expired)) {
                _removePendingRestore(key);
            } else if (expired) {
                Logger.log("qml", "stt", "duck restore abandoned | sink=" + key + " did not return to the ducked volume within " + (_pendingRestoreWindowMs / 1000) + "s");
                _removePendingRestore(key);
            }
        }
    }

    // Polls instead of chaining onSinkChanged + PwNode.onReadyChanged: a
    // swapped-in sink is often not bound yet when it becomes the default, and
    // a returning sink gets its stored volume from WirePlumber some time after
    // it appears. Runs only while a duck or a pending restore exists.
    Timer {
        interval: 250
        repeat: true
        running: root._ducked || root._pendingRestoreCount > 0
        onTriggered: {
            if (root._ducked)
                root._duckSink(Audio.sink);
            root._processPendingRestores();
        }
    }

    // Best-effort restore on QML reload mid-duck, including restores still
    // pending: a sink that is present gets its volume back now, an absent one
    // is lost. A hard shell crash still leaves the volume low — accepted, one
    // keypress fixes it.
    //
    // DIAGNOSTIC NOTE: with stt.ducking.volume at 0 (the current config) that
    // stale state is total silence, and Audio.setVolume force-unmutes, so it
    // presents as "no audio" with the sink unmuted — easily mistaken for the
    // pipewire-pulse start-limit lockout. Tell them apart first:
    // `wpctl get-volume @DEFAULT_AUDIO_SINK@` reading 0.00 while `pactl info`
    // still answers means a stale duck, not a PipeWire fault.
    Component.onDestruction: {
        restore();
        for (const key in _pendingRestores) {
            const node = _findSink(key);
            if (node)
                _restoreSink(node, key, _pendingRestores[key], false);
        }
    }
}
