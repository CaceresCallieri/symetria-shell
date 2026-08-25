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
#   STT_IDE_PID:         Symmetria IDE pid for DIRECT injection into its agent panes
#   STT_IDE_BUF:         Agent slot for direct injection (captured at stop-time)
#
# Always exits 0 — injection failure is non-fatal (clipboard still has text).

ADDRESS="$1"
WINDOW_CLASS="$2"
SUBMIT="${3:-}"
EXPECTED_TEXT="${STT_EXPECTED_TEXT:-}"
NVIM_SOCKET="${STT_NVIM_SOCKET:-}"
NVIM_ACTIVE_BUF="${STT_NVIM_ACTIVE_BUF:--1}"
# Direct-injection target (Symmetria IDE terminal-agent panes): the IDE pid +
# agent slot to address via the IDE's own agent socket (agent-ownership
# inversion, Phase 4 — replaces the old bridge `inject` verb round-trip).
# Mutually exclusive with NVIM_SOCKET by construction (SttJob resolves one
# or the other from the agent's inject_via capability).
IDE_PID="${STT_IDE_PID:-}"
# Mesura Code target pid, for dictation into its composer. Separate from
# IDE_PID because Mesura has no agent panes and no buf to address — the
# conversation on screen is the whole target.
MESURA_PID="${STT_MESURA_PID:-}"
IDE_BUF="${STT_IDE_BUF:--1}"
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

    if ! RESULT=$(timeout 3s nvim --server "$sock" --remote-expr \
        "luaeval('require(\"orchestrator\").stt_inject(_A[1], _A[2], _A[3])', ['$tmpfile', v:$submit, $target_buf])" 2>/dev/null); then
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
    # NOTE: No global EXIT trap here — NVIM_TMPFILE is local to this function,
    # so a trap referencing it at script-exit scope would hit "unbound variable"
    # under set -u. Cleanup is handled explicitly on both return paths below.
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

# ── Direct injection (Symmetria IDE agent panes) ─────────────────────────────
# Connects straight to the owning IDE's agent socket
# ($XDG_RUNTIME_DIR/symmetria-ide-agents-<ide_pid>.sock) and sends an
# stt_inject request: the IDE writes the text into the target claude pane's
# pty (bracketed paste + Enter) and replies an stt_inject_result on the same
# connection. Sets RPC_SUBMITTED from the result so emit_result reports submit
# confirmation like the nvim path. Replaces the old bridge `inject` round-trip
# (agent-ownership inversion, Phase 4) — one socket, one timeout.
try_direct_inject() {
    local submit_bool
    case "$SUBMIT" in
        submit) submit_bool="true" ;;
        *)      submit_bool="false" ;;
    esac

    if [ -z "$IDE_PID" ]; then
        echo "[STT:INJ-DIRECT] no IDE target pid — skipping direct inject" >&2
        return 1
    fi

    local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local sock="${runtime}/symmetria-ide-agents-${IDE_PID}.sock"
    if [ ! -S "$sock" ]; then
        echo "[STT:INJ-DIRECT] IDE socket missing: $sock" >&2
        return 1
    fi

    stt_log "inject" "direct-attempt | idePid=$IDE_PID buf=$IDE_BUF"
    local result
    if ! result=$(STT_IDE_SOCK="$sock" STT_INJECT_SUBMIT="$submit_bool" python3 - <<'PYEOF'
import json, os, socket, sys

request = {
    "type": "stt_inject",
    "buf": int(os.environ.get("STT_IDE_BUF") or -1),
    "text": os.environ.get("STT_EXPECTED_TEXT", ""),
    "submit": os.environ["STT_INJECT_SUBMIT"] == "true",
}
# The IDE stamps its own request_id internally — the direct client needn't send
# one (unlike the bridge path, which correlated replies by request_id).
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
# MUST exceed the IDE's _INJECT_TIMEOUT_SECONDS (5s) so its structured timeout
# reply wins over this socket timeout's bare exception.
sock.settimeout(6.0)
try:
    sock.connect(os.environ["STT_IDE_SOCK"])
    sock.sendall((json.dumps(request) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buf += chunk
    line = buf.split(b"\n", 1)[0].decode("utf-8", "replace")
    response = json.loads(line)
    print(json.dumps(response))
    ok = (
        response.get("type") == "stt_inject_result"
        and response.get("ok") is True
    )
    sys.exit(0 if ok else 1)
except Exception as exc:  # noqa: BLE001 — any failure means no delivery
    print(json.dumps({"ok": False, "error": str(exc)}))
    sys.exit(1)
finally:
    sock.close()
PYEOF
    ); then
        echo "[STT:INJ-DIRECT] direct inject failed | response=$result" >&2
        return 1
    fi

    echo "[STT:INJ-DIRECT] direct inject succeeded | response=$result" >&2
    if echo "$result" | grep -Eq '"submitted"[[:space:]]*:[[:space:]]*true'; then
        RPC_SUBMITTED="true"
    else
        RPC_SUBMITTED="false"
    fi
    return 0
}

# Check if window class is a terminal emulator (or an embedding host that
# exposes nvim over RPC, like symmetria-ide). Must agree with
# SttJob.qml::_isTerminalClass — see the comment there.
is_terminal_class() {
    case "$1" in
        *ghostty*|*warp*|*wezterm*|*alacritty*|*kitty*|*foot*|*konsole*|*xterm*|*urxvt*|*termite*|*sakura*|*tilix*|*terminator*|st-*|*symmetria-ide*)
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
    # In RPC-only mode wl-copy was never run, so the text is NOT in the clipboard.
    # Direct the user to Alt+V (Transcriptions tab re-paste) instead.
    if [ -n "${STT_RPC_ONLY:-}" ]; then
        notify_failure "STT Inject Skipped" "Target window no longer exists. Use Alt+V to paste from Transcriptions."
    else
        notify_failure "STT Inject Skipped" "Target window no longer exists. Text saved to clipboard."
    fi
    emit_result "none" "false"
    exit 0
fi
stt_log "inject" "window-verified | addr=$ADDRESS"
echo "[STT:INJ02] window exists" >&2

CLASS_LOWER=$(echo "$WINDOW_CLASS" | tr '[:upper:]' '[:lower:]')

# ── RPC-only fast path ──────────────────────────────────────────────────────
# When STT_RPC_ONLY=1, the QML caller deliberately skipped wl-copy because
# it expects RPC to handle delivery. There is no clipboard content to fall
# back on — sendshortcut paste would either paste nothing or paste stale
# content. Try RPC; on any failure, surface a clear error and bail. The
# user can re-paste from the Transcriptions tab via Alt+V.
if [ -n "${STT_RPC_ONLY:-}" ]; then
    stt_log "inject" "rpc-only-mode"
    echo "[STT:INJ-RPCONLY] STT_RPC_ONLY=1 — RPC required, no clipboard fallback" >&2

    if ! is_terminal_class "$CLASS_LOWER"; then
        echo "[STT:INJ-RPCONLY] target is not a terminal — RPC unavailable" >&2
        notify_failure "STT Inject Failed" "RPC requires a terminal target. Use Alt+V to paste from Transcriptions."
        emit_result "none" "false"
        exit 0
    fi
    if [ -z "$EXPECTED_TEXT" ]; then
        echo "[STT:INJ-RPCONLY] EXPECTED_TEXT empty — nothing to inject" >&2
        emit_result "none" "false"
        exit 0
    fi

    # Direct-injectable target (IDE agent pane) — IDE socket, no nvim.
    if [ -n "$IDE_PID" ]; then
        if try_direct_inject; then
            stt_log "inject" "direct-success"
            emit_result "direct" "true"
            exit 0
        fi
        stt_log "inject" "direct-failed | rpc-only=bail"
        echo "[STT:INJ-RPCONLY] direct inject failed and STT_RPC_ONLY set — no fallback" >&2
        notify_failure "STT Inject Failed" "Voice → agent pane (direct) failed. Use Alt+V to paste from Transcriptions."
        emit_result "direct" "false"
        exit 0
    fi

    stt_log "inject" "rpc-attempt | socket=$NVIM_SOCKET"
    if try_neovim_inject; then
        stt_log "inject" "rpc-success"
        echo "[STT:INJ-NVIM] Neovim injection succeeded (rpc-only)" >&2
        emit_result "rpc" "true"
        exit 0
    fi
    stt_log "inject" "rpc-failed | rpc-only=bail"
    echo "[STT:INJ-RPCONLY] RPC failed and STT_RPC_ONLY set — no fallback" >&2
    notify_failure "STT Inject Failed" "Voice → buffer (RPC) failed. Use Alt+V to paste from Transcriptions."
    emit_result "rpc" "false"
    exit 0
fi

# ── Mesura Code: dictation into the composer ────────────────────────────────
# Mesura binds its own per-process socket and answers one receipt line, the
# same shape the IDE path uses.
#
# ⚠ Deliberately NOT part of is_terminal_class, and deliberately below the
# wl-copy that has already run. The window class (`mesura-code`) says which
# application is on screen, not whether that build binds a dictation socket —
# an older Mesura, or one already shutting down, has none. Marking the class
# RPC-eligible would skip wl-copy, and those dictations would be lost outright.
# Here a missing socket simply falls through to the Ctrl+V paste below, which
# is what the user already gets for any non-terminal window.
try_mesura_inject() {
    local submit_bool
    case "$SUBMIT" in
        submit) submit_bool="true" ;;
        *)      submit_bool="false" ;;
    esac

    local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local sock="${runtime}/symmetria-mesura-${MESURA_PID}.sock"
    if [ ! -S "$sock" ]; then
        echo "[STT:INJ-MESURA] no Mesura socket at $sock — not a Mesura window" >&2
        return 1
    fi

    stt_log "inject" "mesura-attempt | pid=$MESURA_PID"
    local result
    if ! result=$(STT_MESURA_SOCK="$sock" STT_INJECT_SUBMIT="$submit_bool" python3 - <<'PYEOF'
import json, os, socket, sys

request = {
    "type": "stt_inject",
    "text": os.environ.get("STT_EXPECTED_TEXT", ""),
    "submit": os.environ["STT_INJECT_SUBMIT"] == "true",
}
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
# Must exceed Mesura's own 5s window deadline so its structured answer wins
# over this socket timing out with a bare exception.
sock.settimeout(6.0)
try:
    sock.connect(os.environ["STT_MESURA_SOCK"])
    sock.sendall((json.dumps(request) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    print(buf.decode("utf-8", "replace").strip())
except Exception as exc:  # noqa: BLE001 — any failure is a fall-through
    print(json.dumps({"ok": False, "outcome": "client-error", "detail": str(exc)}))
    sys.exit(1)
finally:
    sock.close()
PYEOF
    ); then
        echo "[STT:INJ-MESURA] client failed" >&2
        return 1
    fi

    echo "[STT:INJ-MESURA] response: $result" >&2
    local ok outcome
    ok=$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("ok"))' 2>/dev/null)
    outcome=$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("outcome",""))' 2>/dev/null)

    # `placed-not-submitted` is a partial success: the words ARE in the
    # composer, so falling through to a Ctrl+V paste would duplicate them.
    # Treat it as delivered and let the submit flag report the truth.
    if [ "$ok" = "True" ] || [ "$outcome" = "placed-not-submitted" ]; then
        case "$outcome" in
            placed-and-submitted) RPC_SUBMITTED="true" ;;
            *)                    RPC_SUBMITTED="false" ;;
        esac
        stt_log "inject" "mesura-success | outcome=$outcome"
        return 0
    fi

    stt_log "inject" "mesura-failed | outcome=$outcome"
    return 1
}

if [ -n "$MESURA_PID" ] && [ -n "$EXPECTED_TEXT" ]; then
    echo "[STT:INJ-MESURA] Mesura target detected — attempting composer delivery" >&2
    if try_mesura_inject; then
        echo "[STT:INJ-MESURA] delivered to the composer — skipping sendshortcut" >&2
        emit_result "mesura" "true"
        exit 0
    fi
    echo "[STT:INJ-MESURA] falling back to sendshortcut paste" >&2
fi

# ── Try Neovim RPC injection for terminal windows ───────────────────────────
# Bypass clipboard entirely by writing directly to Claude Code's terminal stdin
# via Neovim's RPC socket. Only attempted for terminal emulator windows.

if is_terminal_class "$CLASS_LOWER" && [ -n "$EXPECTED_TEXT" ]; then
    if [ -n "$IDE_PID" ]; then
        echo "[STT:INJ-DIRECT] IDE target detected — attempting direct injection" >&2
        if try_direct_inject; then
            stt_log "inject" "direct-success"
            echo "[STT:INJ-DIRECT] direct injection succeeded — skipping sendshortcut" >&2
            emit_result "direct" "true"
            exit 0
        fi
        stt_log "inject" "direct-failed | fallback=sendshortcut"
        echo "[STT:INJ-DIRECT] direct injection failed — falling back to sendshortcut paste" >&2
    else
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
# Only verify clipboard is non-empty (catches silent wl-copy failure).
# A full text comparison would false-positive if the user legitimately copies
# something during the ~2-10s transcription window.

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
