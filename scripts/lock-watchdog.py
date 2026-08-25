#!/usr/bin/env python3
"""Symmetria lock-screen watchdog — the external backstop for lock observability.

WHY THIS EXISTS
---------------
Symmetria's lock screen is an in-process WlSessionLock surface inside the `qs`
shell (see modules/lock/ and services/LockDiagnostics.qml). That means the two
worst failure modes are exactly the ones the shell CANNOT self-report:

  1. `qs` itself dies while the session-lock surface is armed. The compositor
     keeps the session locked (armed but undrawn); the in-process logger and the
     notification center are both gone with it.
  2. The lock surface wedges — its background ScreencopyView never receives a
     frame after resume — while `qs` is technically alive but the surface is a
     transparent sheet over the compositor's blank lock fallback.

This watchdog runs as a systemd *user* service, independent of `qs`, and tails
the heartbeat that LockDiagnostics rewrites every 2s while locked:

    ~/.local/state/symmetria/lock/heartbeat   (JSON: ts, pid, locked,
                                                screencopyHealthy, surfaces)

STUCK RULE (only while heartbeat says locked == true):
  - heartbeat mtime goes stale (> STALE_SECS)        -> qs dead / event loop stalled
  - the recorded pid is no longer alive               -> qs dead (corroborating)
  - screencopyHealthy stays false for > UNHEALTHY_SECS -> wedged blank surface

On a stuck verdict it appends a `watchdog_stuck` event to the same JSON-lines
timeline and best-effort notifies (notify-send only reaches the user if a
notification daemon is alive — it won't be in case 1, so the log is primary).

It does NOT auto-recover (that was an explicit scope decision). Recovery is still
the manual `recover` alias (~/scripts/recover-lockscreen.sh) from a TTY.

BOOT-SAFETY: a leftover `locked:true` heartbeat from a previous crash must not
fire a false alarm on a fresh boot. So the watchdog only alarms for a wedge it
watched go live-then-bad: it must first observe a FRESH locked heartbeat this
episode before any stuck verdict is allowed.
"""

import json
import os
import subprocess
import sys
import time


def _envf(name: str, default: float) -> float:
    try:
        return float(os.environ[name])
    except KeyError, ValueError:
        return default


# Overridable via env (e.g. SYMMETRIA_LOCK_WD_STALE_SECS) for tuning/testing.
POLL_SECS = _envf("SYMMETRIA_LOCK_WD_POLL_SECS", 2.0)
STALE_SECS = _envf(
    "SYMMETRIA_LOCK_WD_STALE_SECS", 8.0
)  # heartbeat mtime age == "qs stopped updating"
UNHEALTHY_SECS = _envf(
    "SYMMETRIA_LOCK_WD_UNHEALTHY_SECS", 12.0
)  # sustained screencopy-blank before alarm


def state_dir() -> str:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(base, "symmetria", "lock")


STATE_DIR = state_dir()
HEARTBEAT = os.path.join(STATE_DIR, "heartbeat")
LOG = os.path.join(STATE_DIR, "lifecycle.jsonl")


def iso_now() -> str:
    # Local time with offset, matching the QML side's toISOString-ish intent but
    # human-readable in the local tz for easier correlation with `journalctl`.
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def log_event(event_type: str, **fields) -> None:
    """Append one JSON line to the shared lifecycle timeline. Never raises."""
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        rec = {"ts": iso_now(), "type": event_type, "source": "watchdog"}
        rec.update(fields)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
    except Exception as exc:
        print(f"[lock-watchdog] log_event failed: {exc}", file=sys.stderr)


def notify(reason: str) -> None:
    """Best-effort desktop notification. Silently no-ops if no daemon is up."""
    try:
        subprocess.run(
            [
                "notify-send",
                "-u",
                "critical",
                "-a",
                "Symmetria Lock Watchdog",
                "Lock screen wedged",
                f"Session locked but not drawing ({reason}).\n"
                "Switch to a TTY (Ctrl+Alt+F2) and run: recover",
            ],
            check=False,
            timeout=5,
        )
    except Exception as exc:
        print(f"[lock-watchdog] notify failed: {exc}", file=sys.stderr)


def read_heartbeat():
    """Return (data: dict, mtime: float) or (None, None) if absent/unreadable."""
    try:
        mtime = os.path.getmtime(HEARTBEAT)
        with open(HEARTBEAT, encoding="utf-8") as fh:
            return json.load(fh), mtime
    except FileNotFoundError:
        return None, None
    except Exception as exc:
        print(f"[lock-watchdog] read_heartbeat failed: {exc}", file=sys.stderr)
        return None, None


def pid_alive(pid) -> bool:
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # exists but not ours to signal
    except Exception:
        return False


def main() -> int:
    log_event(
        "watchdog_started",
        pid=os.getpid(),
        poll=POLL_SECS,
        staleSecs=STALE_SECS,
        unhealthySecs=UNHEALTHY_SECS,
    )

    # Per-episode state. Reset whenever the session is observed unlocked/clean.
    observed_fresh = False  # have we seen a healthy live locked heartbeat?
    unhealthy_since = None  # first tick screencopy was blank while locked
    alarm_latched = False  # alarm fired this episode (avoid spamming)

    while True:
        time.sleep(POLL_SECS)
        data, mtime = read_heartbeat()

        # No heartbeat, or session not locked -> clean state, reset episode.
        if not data or not data.get("locked"):
            if alarm_latched:
                log_event("watchdog_cleared")
            observed_fresh = False
            unhealthy_since = None
            alarm_latched = False
            continue

        # locked == true from here on.
        age = time.time() - (mtime or 0.0)
        pid = data.get("pid")
        alive = pid_alive(pid)
        healthy = bool(data.get("screencopyHealthy"))

        # Establish that we watched a genuinely live lock before trusting any
        # stuck verdict — defeats boot-time leftover-heartbeat false alarms.
        if alive and age <= STALE_SECS:
            observed_fresh = True

        reason = None
        if observed_fresh:
            if not alive:
                reason = "qs_dead"
            elif age > STALE_SECS:
                reason = "heartbeat_stale"
            elif not healthy:
                if unhealthy_since is None:
                    unhealthy_since = time.time()
                elif time.time() - unhealthy_since > UNHEALTHY_SECS:
                    reason = "screencopy_blank"
            else:
                unhealthy_since = None

        if reason and not alarm_latched:
            alarm_latched = True
            log_event(
                "watchdog_stuck",
                reason=reason,
                lockedPid=pid,
                pidAlive=alive,
                heartbeatAgeMs=round(age * 1000),
                screencopyHealthy=healthy,
                surfaces=data.get("surfaces"),
            )
            print(
                f"[lock-watchdog] STUCK LOCK detected: {reason} "
                f"(pid={pid} alive={alive} age={age:.1f}s healthy={healthy})",
                file=sys.stderr,
            )
            notify(reason)
        elif not reason and alarm_latched:
            # Surface recovered on its own while still locked.
            log_event("watchdog_recovered", lockedPid=pid)
            alarm_latched = False


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
