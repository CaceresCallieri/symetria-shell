#!/bin/sh
# Find the Neovim socket for STT injection using PID-scoped search + focus verification.
#
# Algorithm:
#   1. Get all descendant PIDs of the given window PID
#   2. Check if /run/user/$UID/nvim.<pid>.0 exists for each descendant
#   3. Query matching sockets for stt_target_info()
#   4. Filter: has_instances=true AND has_focus=true
#   5. If exactly 1 match → output "<socket> <last_active_buf>"
#   6. If 0 or 2+ → output empty (caller falls back to sendshortcut paste)
#
# Usage: stt-select-socket.sh [window_pid]
#   window_pid: PID of the terminal window (from Hyprland IPC)
#               If 0 or omitted, queries all sockets globally (backward compat)
#
# Output: "<socket_path> <last_active_buf>" or empty string

WINDOW_PID="${1:-0}"
USER_ID=$(id -u 2>/dev/null) || { printf ''; exit 0; }
SOCKET_DIR="/run/user/$USER_ID"

# ── Collect candidate sockets ────────────────────────────────────────────────

# Recursively collect all descendant PIDs of a given PID.
# Uses iterative BFS via pgrep -P to avoid deep recursion.
get_descendant_pids() {
    local queue="$1" result="$1" next_queue="" pid children
    while [ -n "$queue" ]; do
        next_queue=""
        for pid in $queue; do
            children=$(pgrep -P "$pid" 2>/dev/null)
            if [ -n "$children" ]; then
                result="$result $children"
                next_queue="$next_queue $children"
            fi
        done
        queue="$next_queue"
    done
    printf '%s' "$result"
}

CANDIDATE_SOCKETS=""

if [ "$WINDOW_PID" -gt 0 ] 2>/dev/null; then
    # PID-scoped: only check sockets for descendants of the window process
    ALL_PIDS=$(get_descendant_pids "$WINDOW_PID")
    for pid in $ALL_PIDS; do
        sock="$SOCKET_DIR/nvim.${pid}.0"
        [ -S "$sock" ] && CANDIDATE_SOCKETS="$CANDIDATE_SOCKETS $sock"
    done
else
    # No PID given: query all sockets (backward compatibility / manual testing)
    for sock in "$SOCKET_DIR"/nvim.*.0; do
        [ -S "$sock" ] && CANDIDATE_SOCKETS="$CANDIDATE_SOCKETS $sock"
    done
fi

# Trim leading space
CANDIDATE_SOCKETS="${CANDIDATE_SOCKETS# }"

if [ -z "$CANDIDATE_SOCKETS" ]; then
    printf ''
    exit 0
fi

# ── Query each candidate ─────────────────────────────────────────────────────

MATCH_SOCKET=""
MATCH_BUF=""
MATCH_COUNT=0

for sock in $CANDIDATE_SOCKETS; do
    INFO=$(timeout 1s nvim --server "$sock" --remote-expr \
        'luaeval("require(\"orchestrator\").stt_target_info()")' 2>/dev/null)
    [ $? -ne 0 ] && continue

    # Check has_instances=true
    echo "$INFO" | grep -q '"has_instances":true' || continue

    # Check has_focus=true
    echo "$INFO" | grep -q '"has_focus":true' || continue

    # Extract last_active_buf
    BUF=$(echo "$INFO" | grep -o '"last_active_buf":[0-9-]*' | sed 's/"last_active_buf"://')
    [ -z "$BUF" ] && BUF="-1"

    MATCH_COUNT=$((MATCH_COUNT + 1))
    MATCH_SOCKET="$sock"
    MATCH_BUF="$BUF"
done

# ── Output: exactly 1 match → deterministic; otherwise → empty ───────────────

if [ "$MATCH_COUNT" -eq 1 ]; then
    printf '%s %s' "$MATCH_SOCKET" "$MATCH_BUF"
else
    printf ''
fi
