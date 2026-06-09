#!/bin/bash
# Symmetria lock-crash snapshot — the "tell me NOW, it just happened" capture.
#
# WHY: automated detection (services/LockDiagnostics.qml + scripts/lock-watchdog.py)
# can miss failure modes it structurally can't see — a lock that never ENGAGES
# (no heartbeat to go stale), a mild self-healing black-draw, or any crash that
# happened before the instrumented shell was restarted. A human knows a crash
# happened the moment it does. This script lets you capture a full, correlated
# evidence bundle on demand, with ONE command, runnable from a TTY when the GUI
# is wedged (Ctrl+Alt+F2, run this, then `recover`).
#
# It is read-only: it captures state and annotates the timeline. It does NOT
# recover (that's still the `recover` alias / recover-lockscreen.sh).
#
# Usage:  lock-crash-snapshot.sh ["optional free-text note about what you saw"]

set -uo pipefail

NOTE="${*:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/symmetria/lock"
LOG="$STATE_DIR/lifecycle.jsonl"
STAMP="$(date +%Y%m%d-%H%M%S)"
SNAP="$STATE_DIR/crash-snapshot-$STAMP.txt"
ISO="$(date +%Y-%m-%dT%H:%M:%S%z)"

mkdir -p "$STATE_DIR"

# Resolve this user's GRAPHICAL session id (not the TTY we may be running from
# during recovery), so LockedHint/Active reflect the locked desktop session.
graphical_session() {
    local sid
    while read -r sid; do
        case "$(loginctl show-session "$sid" -p Type --value 2>/dev/null)" in
            wayland | x11 | mir)
                echo "$sid"
                return 0
                ;;
        esac
    done < <(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3 == u {print $1}')
    echo "${XDG_SESSION_ID:-}"
}

# 1) Annotate the shared timeline so the marker correlates with everything else.
#    base64 the JSON to dodge quoting hazards (same idiom as the QML/watchdog side).
note_json="$(NOTE="$NOTE" ISO="$ISO" python3 -c 'import json,os; print(json.dumps({"ts":os.environ["ISO"],"type":"user_marked_crash","source":"snapshot","note":os.environ["NOTE"]}))' 2>/dev/null)"
if [[ -n "$note_json" ]]; then
    printf '%s\n' "$note_json" >> "$LOG"
else
    # Fallback if python is somehow unavailable (note is plain text, no quotes).
    printf '{"ts":"%s","type":"user_marked_crash","source":"snapshot","note":"%s"}\n' "$ISO" "${NOTE//\"/}" >> "$LOG"
fi

# Helper: run a command with a hard timeout (hyprctl/loginctl can hang on a wedge).
cap() {
    local title="$1"; shift
    {
        echo "===== $title ====="
        timeout 5 "$@" 2>&1 || echo "(command failed or timed out: $*)"
        echo
    } >> "$SNAP"
}

{
    echo "Symmetria lock-crash snapshot"
    echo "captured: $ISO"
    echo "note: ${NOTE:-(none)}"
    echo
} > "$SNAP"

# 2) Process / locker liveness.
cap "qs (shell) processes"            pgrep -fa "qs -c symmetria"
cap "hyprlock processes"             pgrep -fa hyprlock
cap "lock-watchdog status"           systemctl --user --no-pager status symmetria-lock-watchdog.service

# 3) Session-lock surface state (the core symptom: armed but undrawn).
cap "allow_session_lock_restore"     hyprctl getoption misc:allow_session_lock_restore
cap "loginctl session"               loginctl show-session "$(graphical_session)" -p LockedHint -p Active -p Type

# 4) Output state — directly tests the output-churn / blank-ScreencopyView theory.
#    Raw JSON is agent-readable; the human form is a quick eyeball of dpms state.
cap "hyprctl monitors (json)"        hyprctl monitors all -j
cap "hyprctl monitors (human)"       hyprctl monitors

# 5) The diagnostics the instrumentation produced (if the shell was restarted).
cap "current heartbeat"              cat "$STATE_DIR/heartbeat"
{
    echo "===== last 80 lifecycle.jsonl events ====="
    tail -n 80 "$LOG" 2>/dev/null || echo "(no lifecycle log)"
    echo
} >> "$SNAP"

# 6) System-level corroboration.
cap "coredumps today"                coredumpctl list --since today --no-pager
{
    echo "===== kernel sleep/resume timeline today (HIBERNATE is the prime suspect — see docs) ====="
    journalctl -b --since today 2>/dev/null | grep -iE "PM: suspend entry|PM: suspend exit|PM: hibernation|hibernation exit|Entering sleep state .disk.|Reached target Hibernate|Restarting tasks: Done" | tail -25
    echo
    echo "===== last 120 qs/lock/session journal lines ====="
    journalctl --user -b 2>/dev/null | grep -iE "qs\[|quickshell|hyprlock|session.?lock|segfault|pam_" | tail -120
    echo
} >> "$SNAP"

echo "Lock-crash snapshot written to:"
echo "  $SNAP"
echo "Marker appended to: $LOG"
command -v notify-send >/dev/null && notify-send -a "Symmetria" "Lock-crash snapshot captured" "$SNAP" 2>/dev/null || true
