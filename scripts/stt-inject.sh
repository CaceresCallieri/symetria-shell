#!/bin/bash
set -euo pipefail

for cmd in hyprctl wl-paste; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: required command '$cmd' not found" >&2
        exit 1
    }
done

# Best-effort paste injection for Symmetria STT
# Pastes clipboard content into the target window via hyprctl sendshortcut.
# Assumes clipboard already contains the transcription (wl-copy ran first).
#
# For terminal windows, tries Neovim RPC injection first (bypasses clipboard
# race conditions entirely). Uses PID-scoped socket + focus verification for
# deterministic targeting. Falls back to sendshortcut if no match.
#
# Usage: stt-inject.sh <window_address> <window_class> [submit]
#   window_address: Hyprland window address (e.g., "0x5a3b2c1d")
#   window_class:   Window class string (e.g., "ghostty", "firefox")
#   submit:         If non-empty, send Enter after pasting (auto-submit)
#
# Environment:
#   STT_EXPECTED_TEXT:    The text that should be in the clipboard (for verification)
#   STT_NVIM_SOCKET:     Pre-determined Neovim socket (PID-scoped + focus-verified)
#   STT_NVIM_ACTIVE_BUF: Buffer number captured at stop-time for target_buf parameter
#
# Always exits 0 — injection failure is non-fatal (clipboard still has text).

ADDRESS="$1"
WINDOW_CLASS="$2"
SUBMIT="$3"
EXPECTED_TEXT="${STT_EXPECTED_TEXT:-}"
NVIM_SOCKET="${STT_NVIM_SOCKET:-}"
NVIM_ACTIVE_BUF="${STT_NVIM_ACTIVE_BUF:--1}"
DOWNGRADED=""
# Must be literal "true" or "false" — embedded as JSON boolean by emit_result()
RPC_SUBMITTED="false"

# Unified debug log (shared timeline with QML/Lua/C++)
LOGFILE="${XDG_STATE_HOME:-$HOME/.local/state}/symmetria/debug.log"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
stt_log() { printf '%s [bash:%s] %s\n' "$(date +%H:%M:%S.%3N)" "$1" "$2" >> "$LOGFILE" 2>/dev/null; }

stt_log "inject" "started | addr=$ADDRESS class=$WINDOW_CLASS submit=$SUBMIT"
echo "[STT:INJ01] stt-inject.sh started | address=$ADDRESS | class=$WINDOW_CLASS | submit=$SUBMIT | expectedLen=${#EXPECTED_TEXT} | nvimSocket=$NVIM_SOCKET | nvimActiveBuf=$NVIM_ACTIVE_BUF" >&2

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
# Injects text directly into a Claude Code terminal via Neovim's RPC socket
# and the Orchestrator plugin. Bypasses clipboard entirely.
#
# Uses pre-determined socket from stop-time (PID-scoped + focus-verified).
# No real-time re-selection — if no socket was captured, falls back to paste.

# Attempt RPC injection on a single Neovim socket.
# Args: $1=socket $2=tmpfile $3=submit_bool ("true"/"false") $4=target_buf (number, -1=auto)
# Returns 0 on success, 1 on failure. Caller cleans up tmpfile.
_try_rpc() {
    local sock="$1" tmpfile="$2" submit="$3" target_buf="$4"
    [ -z "$target_buf" ] && target_buf="-1"

    # Reject paths that would break single-quoted Lua string interpolation
    case "$tmpfile" in
        *\'*) echo "[STT:INJ-NVIM] tmpfile path contains single quote — aborting RPC" >&2; return 1 ;;
        *' '*) echo "[STT:INJ-NVIM] tmpfile path contains spaces — aborting RPC" >&2; return 1 ;;
    esac

    RESULT=$(timeout 3s nvim --server "$sock" --remote-expr \
        "luaeval('require(\"orchestrator\").stt_inject(_A[1], _A[2], _A[3])', ['$tmpfile', v:$submit, $target_buf])" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "[STT:INJ-NVIM] RPC failed on $sock (target_buf=$target_buf)" >&2
        return 1
    fi

    echo "[STT:INJ-NVIM] response from $sock (target_buf=$target_buf): $RESULT" >&2

    if echo "$RESULT" | grep -q '"ok":true'; then
        INSTANCE_CWD=$(echo "$RESULT" | grep -o '"instance_cwd":"[^"]*"' | sed 's/"instance_cwd":"//;s/"$//')
        if echo "$RESULT" | grep -q '"submitted":true'; then
            RPC_SUBMITTED="true"
        else
            RPC_SUBMITTED="false"
        fi
        echo "[STT:INJ-NVIM] injection succeeded | socket=$sock | cwd=$INSTANCE_CWD | target_buf=$target_buf | submitted=$RPC_SUBMITTED" >&2
        return 0
    fi

    ERROR=$(echo "$RESULT" | grep -o '"error":"[^"]*"' | sed 's/"error":"//' | sed 's/"$//')
    echo "[STT:INJ-NVIM] injection failed | socket=$sock | error=$ERROR | target_buf=$target_buf" >&2
    return 1
}

try_neovim_inject() {
    local submit_bool
    case "$SUBMIT" in
        submit) submit_bool="true" ;;
        *)      submit_bool="false" ;;
    esac

    # Require pre-determined socket (PID-scoped + focus-verified at stop-time).
    # No fallback to real-time re-selection — if the socket wasn't captured,
    # the user wasn't in a Neovim terminal when they pressed stop.
    if [ -z "$NVIM_SOCKET" ]; then
        echo "[STT:INJ-NVIM] no pre-determined socket — skipping RPC" >&2
        return 1
    fi

    if [ ! -S "$NVIM_SOCKET" ]; then
        echo "[STT:INJ-NVIM] pre-determined socket gone: $NVIM_SOCKET" >&2
        return 1
    fi

    # Write text to temp file (avoids all shell/Lua escaping issues)
    local NVIM_TMPFILE
    NVIM_TMPFILE=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/stt-nvim-inject.XXXXXX")
    trap 'rm -f "$NVIM_TMPFILE"' EXIT
    if [ -z "$NVIM_TMPFILE" ]; then
        echo "[STT:INJ-NVIM] failed to create temp file" >&2
        return 1
    fi
    printf '%s' "$EXPECTED_TEXT" > "$NVIM_TMPFILE"
    echo "[STT:INJ-NVIM] wrote ${#EXPECTED_TEXT} chars to $NVIM_TMPFILE | socket=$NVIM_SOCKET | activeBuf=$NVIM_ACTIVE_BUF" >&2

    if _try_rpc "$NVIM_SOCKET" "$NVIM_TMPFILE" "$submit_bool" "$NVIM_ACTIVE_BUF"; then
        rm -f "$NVIM_TMPFILE"
        return 0
    fi

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

# Emit structured JSON result to stdout for QML parsing.
# Args: $1=path ("rpc"|"paste"|"none") $2=success ("true"|"false")
emit_result() {
    local path="$1" success="$2"
    local downgraded="${DOWNGRADED:-false}"
    local submitted="${RPC_SUBMITTED:-false}"
    printf '{"path":"%s","success":%s,"downgraded":%s,"submitted":%s}\n' \
        "$path" "$success" "$downgraded" "$submitted"
}

# ── Validate arguments ───────────────────────────────────────────────────────

if [ -z "$ADDRESS" ]; then
    echo "[STT:INJ01] ABORT — missing window address" >&2
    emit_result "none" "false"
    exit 0
fi

# ── Verify target window still exists ────────────────────────────────────────

echo "[STT:INJ02] checking if window $ADDRESS still exists..." >&2
if ! hyprctl clients -j 2>/dev/null | grep -qF "\"address\": \"$ADDRESS\""; then
    echo "[STT:INJ02] ABORT — target window $ADDRESS no longer exists" >&2
    notify_failure "STT Inject Skipped" "Target window no longer exists. Text saved to clipboard."
    emit_result "none" "false"
    exit 0
fi
stt_log "inject" "window-verified | addr=$ADDRESS"
echo "[STT:INJ02] window exists" >&2

# ── Try Neovim RPC injection for terminal windows ───────────────────────────
# Bypass clipboard entirely by writing directly to Claude Code's terminal stdin
# via Neovim's RPC socket. Only attempted for terminal emulator windows.

CLASS_LOWER=$(echo "$WINDOW_CLASS" | tr '[:upper:]' '[:lower:]')

if is_terminal_class "$CLASS_LOWER" && [ -n "$EXPECTED_TEXT" ]; then
    stt_log "inject" "rpc-attempt | socket=$NVIM_SOCKET"
    echo "[STT:INJ-NVIM] terminal class detected — attempting Neovim RPC injection" >&2
    if try_neovim_inject; then
        stt_log "inject" "rpc-success"
        echo "[STT:INJ-NVIM] Neovim injection succeeded — skipping sendshortcut" >&2
        emit_result "rpc" "true"
        exit 0
    fi
    stt_log "inject" "rpc-failed | fallback=sendshortcut"
    echo "[STT:INJ-NVIM] Neovim injection failed — falling back to sendshortcut paste" >&2
fi

# ── Downgrade submit on sendshortcut path ────────────────────────────────────
# Submit (auto-Enter) is only safe via Neovim RPC where orchestrator handles
# injection+submission atomically. On the sendshortcut path, paste delivery
# is unconfirmed — sending Enter risks submitting to the wrong input.
if [ "$SUBMIT" = "submit" ]; then
    echo "[STT:INJ-DOWN] downgrading submit→inject (sendshortcut has no paste confirmation)" >&2
    SUBMIT=""
    DOWNGRADED="true"
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

# ── Pre-paste clipboard sanity check ─────────────────────────────────────────
# Light check: only verify clipboard is non-empty (catches silent wl-copy failure).
# Full text comparison is deferred to INJ09 (before Enter) where the async gap
# makes it genuinely useful. Doing a full comparison here would false-positive
# if the user legitimately copies something during the ~2-10s transcription window.

CLIP_CHECK=$(wl-paste --no-newline 2>/dev/null)
if [ -z "$CLIP_CHECK" ]; then
    echo "[STT:INJ05] clipboard is EMPTY — wl-copy may have failed silently" >&2
    notify_failure "STT Inject Failed" "Clipboard is empty. wl-copy may have failed silently."
    emit_result "none" "false"
    exit 0
fi
echo "[STT:INJ05] clipboard non-empty (len=${#CLIP_CHECK}) — proceeding" >&2

# ── Send paste ───────────────────────────────────────────────────────────────

# 150ms: allows wl-copy data + Hyprland's internal focus-change data_offer to propagate
echo "[STT:INJ06] sleeping 150ms for clipboard propagation..." >&2
sleep 0.15

stt_log "inject" "paste-send | shortcut=$SHORTCUT addr=$ADDRESS"
echo "[STT:INJ07] sending paste: hyprctl dispatch sendshortcut $SHORTCUT, address:$ADDRESS" >&2
PASTE_RESULT=$(hyprctl dispatch sendshortcut "$SHORTCUT, address:$ADDRESS" 2>&1)
PASTE_CODE=$?
echo "[STT:INJ07] paste result | exit=$PASTE_CODE | output=$PASTE_RESULT" >&2

if [ "$PASTE_CODE" -ne 0 ]; then
    notify_failure "STT Inject Failed" "sendshortcut paste failed (exit $PASTE_CODE). Text saved to clipboard."
    emit_result "paste" "false"
    exit 0
fi

# Auto-submit is only supported via the Neovim RPC path (above). On the
# sendshortcut path, SUBMIT is always cleared by the downgrade logic.
echo "[STT:INJ08] paste complete — done (submit only via RPC)" >&2
emit_result "paste" "true"

stt_log "inject" "finished"
echo "[STT:INJ11] stt-inject.sh finished" >&2
exit 0
