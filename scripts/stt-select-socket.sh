#!/bin/sh
# Find the Neovim socket most likely to be the STT target.
# Queries stt_target_info() on each socket and picks the one with
# the highest focus_timestamp that has Claude Code instances.
# Outputs socket path to stdout (empty if none found).

BEST_SOCKET=""
BEST_TIMESTAMP=0

USER_ID=$(id -u 2>/dev/null) || { printf ''; exit 0; }

for sock in $(find "/run/user/$USER_ID/" -maxdepth 1 -name 'nvim.*.0' 2>/dev/null); do
    INFO=$(timeout 1s nvim --server "$sock" --remote-expr \
        'luaeval("require(\"orchestrator\").stt_target_info()")' 2>/dev/null)
    [ $? -ne 0 ] && continue

    HAS_INSTANCES=$(echo "$INFO" | grep -o '"has_instances":true')
    [ -z "$HAS_INSTANCES" ] && continue

    TIMESTAMP=$(echo "$INFO" | grep -o '"focus_timestamp":[0-9]*' | sed 's/"focus_timestamp"://')
    [ -z "$TIMESTAMP" ] && continue

    if [ "$TIMESTAMP" -gt "$BEST_TIMESTAMP" ] 2>/dev/null; then
        BEST_TIMESTAMP="$TIMESTAMP"
        BEST_SOCKET="$sock"
    fi
done

printf '%s' "$BEST_SOCKET"
