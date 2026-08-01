pragma ComponentBehavior: Bound

import qs.components
import qs.components.effects
import qs.services
import qs.config
import Quickshell.Wayland
import QtQuick

// The lock screen is three layers:
//
//   1. ScreencopyView  — a snapshot of the desktop as it was
//   2. BeamsBackground — metallic beams that WIPE IN over that snapshot
//   3. PasswordPrompt  — a single password field, arriving once the wipe lands
//
// Locking plays 1 → 2 → 3; unlocking plays it backwards, so the beams retract
// and hand the desktop back. The wipe is the whole point of the screen: the
// beams are what covers your session, and watching them do it is the effect.
WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running

    // Per-output identity for diagnostics. WlSessionLockSurface is created once
    // per screen; the surface is torn down and recreated when Hyprland removes/
    // re-adds outputs across suspend/resume — the prime suspect window.
    readonly property string screenName: root.screen?.name ?? "unknown"

    color: "transparent"

    Component.onCompleted: LockDiagnostics.markSurfaceCreated(root.screenName)
    Component.onDestruction: LockDiagnostics.markSurfaceDestroyed(root.screenName)

    Connections {
        target: root.lock

        function onUnlock(): void {
            // Stop the intro first: unlock can land DURING it (fingerprint, or
            // an IPC/shortcut unlock right after locking). Both sequences drive
            // beams.reveal and the prompt's opacity/scale, so leaving initAnim
            // running lets them fight frame to frame — the reveal can animate
            // back UP after the retract has started.
            initAnim.stop();
            unlockAnim.start();
        }
    }

    SequentialAnimation {
        id: initAnim

        running: true

        Anim {
            target: beams
            property: "reveal"
            from: 0
            to: 1
            duration: Config.lock.beams.revealDuration
            easing.bezierCurve: Appearance.anim.curves.standard
        }
        ParallelAnimation {
            Anim {
                target: prompt
                property: "opacity"
                to: 1
                duration: Appearance.anim.durations.large
            }
            Anim {
                target: prompt
                property: "scale"
                to: 1
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        }
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            Anim {
                target: prompt
                property: "opacity"
                to: 0
                duration: Appearance.anim.durations.small
            }
            Anim {
                target: prompt
                property: "scale"
                to: 0.9
                duration: Appearance.anim.durations.normal
            }
        }
        Anim {
            target: beams
            property: "reveal"
            to: 0
            duration: Config.lock.beams.revealDuration
            easing.bezierCurve: Appearance.anim.curves.standard
        }
        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    // Desktop snapshot — what the beams cover.
    //
    // Deliberately NOT blurred. It was, on the theory that the desktop is
    // briefly legible during the wipe; in practice the blur added nothing to
    // the look and cost a full-screen MultiEffect pass. The tradeoff is real
    // though: for the ~1.4s of the wipe, the uncovered part of your session is
    // readable to anyone watching. Re-add a `layer.effect: MultiEffect` here if
    // that ever matters.
    ScreencopyView {
        id: background

        anchors.fill: parent
        captureSource: root.screen

        // Explicit, because the whole design depends on it: this is a SNAPSHOT
        // of the desktop at lock time. If it ever went live, the view would
        // capture the lock surface it sits inside — a feedback loop plus
        // continuous capture cost for the entire lock session.
        live: false

        // THE smoking-gun signal. If hasContent never flips true while locked,
        // the lock is "armed but undrawn" — the exact crash signature — with qs
        // still alive. Logged for post-mortem and fed into the heartbeat the
        // external watchdog tails.
        //
        // NOTE: this view is no longer the surface's only opaque content — the
        // beams above it are opaque once revealed. So a blank ScreencopyView
        // would now show as beams-over-nothing rather than a fully black screen.
        // The signal is still worth having; its symptom just changed.
        onHasContentChanged: LockDiagnostics.markScreencopy(root.screenName, hasContent)
    }

    // One instance per output, by design. The beam bands derive from this
    // surface's own UV and aspect, so on a multi-monitor setup the pattern does
    // NOT span the desktop — each screen gets its own beams and its own wipe.
    // Making it span would mean feeding global desktop coordinates through
    // uResolution/qt_TexCoord0. Recorded so it isn't refiled as a bug.
    BeamsBackground {
        id: beams

        anchors.fill: parent
        cfg: Config.lock.beams
        reveal: 0
    }

    PasswordPrompt {
        id: prompt

        anchors.centerIn: parent
        surface: root

        opacity: 0
        scale: 0.9
    }
}
