#!/bin/bash
# Find the Neovim socket for STT injection using PID-scoped search + focus verification.
#
# Algorithm:
#   1. Get all descendant PIDs of the given window PID
#   2. Check if /run/user/$UID/nvim.<pid>.0 exists for each descendant
#   3. Query matching sockets for stt_target_info()
#   4. Filter: has_instances=true AND has_focus=true
#   5. If exactly 1 match → output "<socket>\t<buf>\t<title>\t<cwd>" (tab-delimited)
#   6. If 0 or 2+ → output nothing (caller falls back to sendshortcut paste)
#
# Usage: stt-select-socket.sh [window_pid]
#   window_pid: PID of the terminal window (from Hyprland IPC)
#               If 0 or omitted, queries all sockets globally (backward compat)
#
# Output: "<socket_path>\t<last_active_buf>\t<instance_title>\t<instance_cwd>" (tab-delimited)
#         or empty string on failure/no match

WINDOW_PID="${1:-0}"
USER_ID=$(id -u 2>/dev/null) || exit 0
SOCKET_DIR="/run/user/$USER_ID"

# ── Collect candidate sockets ────────────────────────────────────────────────

# Recursively collect all descendant PIDs of a given PID.
# Uses iterative BFS via pgrep -P to avoid deep recursion.
get_descendant_pids() {
    local queue="$1" result="$1" next_queue="" pid children child
    local seen=" $1 "
    while [ -n "$queue" ]; do
        next_queue=""
        for pid in $queue; do
            children=$(pgrep -P "$pid" 2>/dev/null)
            for child in $children; do
                case "$seen" in
                    *" $child "*) continue ;;
                esac
                seen="$seen$child "
                result="$result $child"
                next_queue="$next_queue $child"
            done
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
    exit 0
fi

# ── Query each candidate ─────────────────────────────────────────────────────

RESULT_SOCKET=""
RESULT_BUF=""
RESULT_TITLE=""
RESULT_CWD=""
MATCH_COUNT=0

for sock in $CANDIDATE_SOCKETS; do
    INFO=$(timeout 1s nvim --server "$sock" --remote-expr \
        'luaeval("require(\"orchestrator\").stt_target_info()")' 2>/dev/null)
    [ $? -ne 0 ] && continue

    # Parse all fields in one jq pass: "has_instances has_focus last_active_buf title cwd"
    # Using tab-delimited output to handle spaces in title/cwd
    PARSED=$(printf '%s' "$INFO" | jq -r \
        '[.has_instances, .has_focus, (.last_active_buf // -1), (.instance_title // ""), (.instance_cwd // "")] | @tsv' 2>/dev/null)
    [ $? -ne 0 ] && continue

    IFS=$'\t' read -r HAS_INST HAS_FOCUS BUF TITLE CWD <<< "$PARSED"

    # Normalize: jq @tsv outputs empty field for JSON null, not "false"
    [ -z "$HAS_INST"  ] && HAS_INST="false"
    [ -z "$HAS_FOCUS" ] && HAS_FOCUS="false"
    [ "$HAS_INST" = "true" ] || continue
    [ "$HAS_FOCUS" = "true" ] || continue

    MATCH_COUNT=$((MATCH_COUNT + 1))
    RESULT_SOCKET="$sock"
    RESULT_BUF="$BUF"
    RESULT_TITLE="$TITLE"
    RESULT_CWD="$CWD"
done

# ── Output: exactly 1 match → deterministic; otherwise → empty ───────────────

if [ "$MATCH_COUNT" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s' "$RESULT_SOCKET" "$RESULT_BUF" "$RESULT_TITLE" "$RESULT_CWD"
elif [ "$MATCH_COUNT" -gt 1 ]; then
    echo "[STT:SEL] ambiguous: $MATCH_COUNT sockets matched — falling back to paste" >&2
else
    echo "[STT:SEL] no socket matched for PID=$WINDOW_PID — falling back to paste" >&2
fi
