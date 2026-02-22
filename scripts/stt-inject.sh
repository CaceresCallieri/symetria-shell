#!/bin/sh
# Best-effort paste injection for Symmetria STT
# Pastes clipboard content into the target window via hyprctl sendshortcut.
# Assumes clipboard already contains the transcription (wl-copy ran first).
#
# For terminal windows, tries Neovim RPC injection first (bypasses clipboard
# race conditions entirely). Falls back to sendshortcut if no Neovim/Orchestrator
# instance is found.
#
# Usage: stt-inject.sh <window_address> <window_class> [submit]
#   window_address: Hyprland window address (e.g., "0x5a3b2c1d")
#   window_class:   Window class string (e.g., "ghostty", "firefox")
#   submit:         If non-empty, send Enter after pasting (auto-submit)
#
# Environment:
#   STT_EXPECTED_TEXT: The text that should be in the clipboard (for verification)
#   STT_NVIM_SOCKET:  Pre-determined Neovim socket (captured at stop-time; skips Pass 1)
#
# Always exits 0 — injection failure is non-fatal (clipboard still has text).

ADDRESS="$1"
WINDOW_CLASS="$2"
SUBMIT="$3"
EXPECTED_TEXT="${STT_EXPECTED_TEXT:-}"
NVIM_SOCKET="${STT_NVIM_SOCKET:-}"

echo "[STT:INJ01] stt-inject.sh started | address=$ADDRESS | class=$WINDOW_CLASS | submit=$SUBMIT | expectedLen=${#EXPECTED_TEXT} | nvimSocket=$NVIM_SOCKET" >&2

# ── Helpers ──────────────────────────────────────────────────────────────────

notify_failure() {
    local title="$1"
    local body="$2"
    echo "[STT:INJ-NOTIFY] $title: $body" >&2
    notify-send -a "Symmetria STT" -u normal -i dialog-warning "$title" "$body" 2>/dev/null &
}

# Verify clipboard matches expected text. Returns 0 if OK, 1 if mismatch.
verify_clipboard() {
    local stage="$1"
    if [ -z "$EXPECTED_TEXT" ]; then
        echo "[STT:$stage] no expected text provided — skipping verification" >&2
        return 0
    fi
    ACTUAL_TEXT=$(wl-paste --no-newline 2>/dev/null)
    ACTUAL_LEN=${#ACTUAL_TEXT}
    EXPECTED_LEN=${#EXPECTED_TEXT}
    if [ "$ACTUAL_TEXT" = "$EXPECTED_TEXT" ]; then
        echo "[STT:$stage] clipboard verified OK | len=$ACTUAL_LEN" >&2
        return 0
    else
        ACTUAL_PREVIEW=$(printf '%.60s' "$ACTUAL_TEXT")
        EXPECTED_PREVIEW=$(printf '%.60s' "$EXPECTED_TEXT")
        echo "[STT:$stage] clipboard MISMATCH | expected_len=$EXPECTED_LEN actual_len=$ACTUAL_LEN" >&2
        echo "[STT:$stage]   expected: $EXPECTED_PREVIEW" >&2
        echo "[STT:$stage]   actual:   $ACTUAL_PREVIEW" >&2
        return 1
    fi
}

# ── Neovim RPC injection ─────────────────────────────────────────────────────
# Tries to inject text directly into a Claude Code terminal via Neovim's RPC
# socket and the Orchestrator plugin. Bypasses clipboard entirely.
# Returns 0 on success, 1 on failure (caller should fall back to sendshortcut).

try_neovim_inject() {
    local submit_bool
    case "$SUBMIT" in
        submit) submit_bool="true" ;;
        *)      submit_bool="false" ;;
    esac

    # Write text to temp file (avoids all shell/Lua escaping issues)
    local NVIM_TMPFILE
    NVIM_TMPFILE=$(mktemp /tmp/stt-nvim-inject.XXXXXX)
    if [ -z "$NVIM_TMPFILE" ]; then
        echo "[STT:INJ-NVIM] failed to create temp file" >&2
        return 1
    fi
    printf '%s' "$EXPECTED_TEXT" > "$NVIM_TMPFILE"
    echo "[STT:INJ-NVIM] wrote ${#EXPECTED_TEXT} chars to $NVIM_TMPFILE" >&2

    # Enumerate Neovim sockets
    local NVIM_SOCKETS
    NVIM_SOCKETS=$(find "/run/user/$(id -u)/" -maxdepth 1 -name 'nvim.*.0' 2>/dev/null)
    if [ -z "$NVIM_SOCKETS" ]; then
        echo "[STT:INJ-NVIM] no Neovim sockets found" >&2
        rm -f "$NVIM_TMPFILE"
        return 1
    fi
    echo "[STT:INJ-NVIM] found sockets: $(echo "$NVIM_SOCKETS" | tr '\n' ' ')" >&2

    # ── Pass 1: Determine target socket ────────────────────────────────────
    local BEST_SOCKET=""
    local BEST_TIMESTAMP=0

    if [ -n "$NVIM_SOCKET" ]; then
        # Pre-determined socket from stop-time capture (avoids focus drift during transcription)
        echo "[STT:INJ-NVIM] using pre-determined socket: $NVIM_SOCKET" >&2
        BEST_SOCKET="$NVIM_SOCKET"
    else
        # Fallback: query all sockets for focus info at inject-time
        # Each Neovim tracks when it last received FocusGained (terminal focus-in).
        # We pick the most recently focused one that has Claude instances.
        for sock in $NVIM_SOCKETS; do
            echo "[STT:INJ-NVIM] pass 1: querying $sock" >&2

            INFO=$(timeout 1s nvim --server "$sock" --remote-expr \
                'luaeval("require(\"orchestrator\").stt_target_info()")' 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "[STT:INJ-NVIM] pass 1: $sock RPC failed — skipping" >&2
                continue
            fi

            echo "[STT:INJ-NVIM] pass 1: $sock info=$INFO" >&2

            # Parse has_instances and focus_timestamp from compact JSON
            HAS_INSTANCES=$(echo "$INFO" | grep -o '"has_instances":true')
            TIMESTAMP=$(echo "$INFO" | grep -o '"focus_timestamp":[0-9]*' | sed 's/"focus_timestamp"://')

            if [ -z "$HAS_INSTANCES" ]; then
                echo "[STT:INJ-NVIM] pass 1: $sock has no Claude instances — skipping" >&2
                continue
            fi

            if [ -z "$TIMESTAMP" ]; then
                echo "[STT:INJ-NVIM] pass 1: $sock missing timestamp — skipping" >&2
                continue
            fi

            if [ "$TIMESTAMP" -gt "$BEST_TIMESTAMP" ] 2>/dev/null; then
                BEST_TIMESTAMP="$TIMESTAMP"
                BEST_SOCKET="$sock"
                echo "[STT:INJ-NVIM] pass 1: new best | socket=$sock timestamp=$TIMESTAMP" >&2
            fi
        done
    fi

    # ── Pass 2: Inject on the winning socket only ─────────────────────────
    if [ -z "$BEST_SOCKET" ]; then
        echo "[STT:INJ-NVIM] no socket with Claude instances found" >&2
        rm -f "$NVIM_TMPFILE"
        return 1
    fi

    echo "[STT:INJ-NVIM] selected socket: $BEST_SOCKET (focus_timestamp=$BEST_TIMESTAMP)" >&2

    RESULT=$(timeout 2s nvim --server "$BEST_SOCKET" --remote-expr \
        "luaeval('require(\"orchestrator\").stt_inject(_A[1], _A[2])', ['$NVIM_TMPFILE', v:$submit_bool])" 2>/dev/null)
    RPC_CODE=$?

    if [ "$RPC_CODE" -ne 0 ]; then
        echo "[STT:INJ-NVIM] pass 2: RPC failed (exit=$RPC_CODE)" >&2
        rm -f "$NVIM_TMPFILE"
        return 1
    fi

    echo "[STT:INJ-NVIM] pass 2: response=$RESULT" >&2

    if echo "$RESULT" | grep -q '"ok":true'; then
        INSTANCE_CWD=$(echo "$RESULT" | grep -o '"instance_cwd":"[^"]*"' | sed 's/"instance_cwd":"//' | sed 's/"$//')
        echo "[STT:INJ-NVIM] injection succeeded | socket=$BEST_SOCKET | cwd=$INSTANCE_CWD" >&2
        return 0
    fi

    # Parse error for logging
    ERROR=$(echo "$RESULT" | grep -o '"error":"[^"]*"' | sed 's/"error":"//' | sed 's/"$//')
    echo "[STT:INJ-NVIM] injection failed | socket=$BEST_SOCKET | error=$ERROR" >&2
    rm -f "$NVIM_TMPFILE"
    return 1
}

# Check if window class is a terminal emulator
is_terminal_class() {
    case "$1" in
        *ghostty*|*warp*|*wezterm*|*alacritty*|*kitty*|*foot*|*konsole*|xterm*|urxvt*|*termite*|*sakura*|*tilix*|*terminator*|st-*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ── Validate arguments ───────────────────────────────────────────────────────

if [ -z "$ADDRESS" ]; then
    echo "[STT:INJ01] ABORT — missing window address" >&2
    exit 0
fi

# ── Verify target window still exists ────────────────────────────────────────

echo "[STT:INJ02] checking if window $ADDRESS still exists..." >&2
if ! hyprctl clients -j 2>/dev/null | grep -qF "\"address\": \"$ADDRESS\""; then
    echo "[STT:INJ02] ABORT — target window $ADDRESS no longer exists" >&2
    notify_failure "STT Inject Skipped" "Target window no longer exists. Text saved to clipboard."
    exit 0
fi
echo "[STT:INJ02] window exists" >&2

# ── Try Neovim RPC injection for terminal windows ───────────────────────────
# Bypass clipboard entirely by writing directly to Claude Code's terminal stdin
# via Neovim's RPC socket. Only attempted for terminal emulator windows.

CLASS_LOWER=$(echo "$WINDOW_CLASS" | tr '[:upper:]' '[:lower:]')

if is_terminal_class "$CLASS_LOWER" && [ -n "$EXPECTED_TEXT" ]; then
    echo "[STT:INJ-NVIM] terminal class detected — attempting Neovim RPC injection" >&2
    if try_neovim_inject; then
        echo "[STT:INJ-NVIM] Neovim injection succeeded — skipping sendshortcut" >&2
        exit 0
    fi
    echo "[STT:INJ-NVIM] Neovim injection failed — falling back to sendshortcut paste" >&2
fi

# ── Determine paste shortcut ─────────────────────────────────────────────────
# Uses is_terminal_class() as single source of truth for terminal detection.

if is_terminal_class "$CLASS_LOWER"; then
    SHORTCUT="CTRL SHIFT, V"
else
    SHORTCUT="CTRL, V"
fi
echo "[STT:INJ03] shortcut resolved | class_lower=$CLASS_LOWER | shortcut=$SHORTCUT" >&2

# ── Diagnostics: current focus and clipboard state ───────────────────────────

ACTIVE_ADDR=$(hyprctl activewindow -j 2>/dev/null | grep -o '"address": "[^"]*"' | head -1)
echo "[STT:INJ04] active window at inject time: $ACTIVE_ADDR | target: $ADDRESS" >&2

# ── Pre-paste clipboard verification ─────────────────────────────────────────

if ! verify_clipboard "INJ05"; then
    notify_failure "STT Inject Failed" "Clipboard doesn't contain transcribed text. Something overwrote it between copy and paste."
    exit 0
fi

# ── Send paste ───────────────────────────────────────────────────────────────

# 150ms: allows wl-copy data + Hyprland's internal focus-change data_offer to propagate
echo "[STT:INJ06] sleeping 150ms for clipboard propagation..." >&2
sleep 0.15

echo "[STT:INJ07] sending paste: hyprctl dispatch sendshortcut $SHORTCUT, address:$ADDRESS" >&2
PASTE_RESULT=$(hyprctl dispatch sendshortcut "$SHORTCUT, address:$ADDRESS" 2>&1)
PASTE_CODE=$?
echo "[STT:INJ07] paste result | exit=$PASTE_CODE | output=$PASTE_RESULT" >&2

if [ "$PASTE_CODE" -ne 0 ]; then
    notify_failure "STT Inject Failed" "sendshortcut paste failed (exit $PASTE_CODE). Text saved to clipboard."
    exit 0
fi

# ── Auto-submit: guarded Enter ───────────────────────────────────────────────

if [ "$SUBMIT" = "submit" ]; then
    # 250ms: allow application to process pasted text before verifying + submitting
    echo "[STT:INJ08] submit mode — sleeping 250ms for app to process paste..." >&2
    sleep 0.25

    # Re-verify window still exists before sending Enter
    if ! hyprctl clients -j 2>/dev/null | grep -qF "\"address\": \"$ADDRESS\""; then
        echo "[STT:INJ08] target window closed during paste delay — skipping Enter" >&2
        notify_failure "STT Submit Skipped" "Target window closed after paste. Text was pasted but Enter was not sent."
        exit 0
    fi

    # Re-verify clipboard is still intact (not overwritten by something else)
    if ! verify_clipboard "INJ09"; then
        echo "[STT:INJ09] clipboard changed between paste and Enter — skipping Enter" >&2
        notify_failure "STT Submit Skipped" "Clipboard was overwritten after paste. Enter was not sent to avoid submitting wrong content."
        exit 0
    fi

    echo "[STT:INJ10] sending Enter: hyprctl dispatch sendshortcut , Return, address:$ADDRESS" >&2
    ENTER_RESULT=$(hyprctl dispatch sendshortcut ", Return, address:$ADDRESS" 2>&1)
    ENTER_CODE=$?
    echo "[STT:INJ10] Enter result | exit=$ENTER_CODE | output=$ENTER_RESULT" >&2

    if [ "$ENTER_CODE" -ne 0 ]; then
        notify_failure "STT Submit Failed" "Paste succeeded but Enter key failed (exit $ENTER_CODE). Text was pasted but not submitted."
    fi
else
    echo "[STT:INJ08] submit not requested — done (clipboard+paste only)" >&2
fi

echo "[STT:INJ11] stt-inject.sh finished" >&2
exit 0
