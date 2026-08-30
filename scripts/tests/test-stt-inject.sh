#!/bin/bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT_UNDER_TEST="$REPOSITORY_ROOT/scripts/stt-inject.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/symmetria-stt-inject.XXXXXX")
MOCK_BIN="$TEST_ROOT/bin"
MOCK_LOG="$TEST_ROOT/hyprctl.log"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$MOCK_BIN" "$TEST_ROOT/state"

cat > "$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
    clients)
        if [[ "${MOCK_WINDOW_PRESENT:-1}" == "1" ]]; then
            printf '[{"address": "0xabc", "class": "firefox"}]\n'
        else
            printf '[]\n'
        fi
        ;;
    activewindow)
        printf '{"address": "0xother"}\n'
        ;;
    dispatch)
        printf '%s\n' "$*" >> "$MOCK_LOG"
        printf 'ok\n'
        ;;
    *)
        exit 1
        ;;
esac
MOCK

cat > "$MOCK_BIN/wl-paste" <<'MOCK'
#!/bin/bash
printf 'dictated words'
MOCK

cat > "$MOCK_BIN/notify-send" <<'MOCK'
#!/bin/bash
exit 0
MOCK

cat > "$MOCK_BIN/timeout" <<'MOCK'
#!/bin/bash
shift
exec "$@"
MOCK

cat > "$MOCK_BIN/nvim" <<'MOCK'
#!/bin/bash
printf '{"ok":true,"submitted":true,"instance_cwd":"/work/project"}\n'
MOCK

chmod +x \
    "$MOCK_BIN/hyprctl" \
    "$MOCK_BIN/wl-paste" \
    "$MOCK_BIN/notify-send" \
    "$MOCK_BIN/timeout" \
    "$MOCK_BIN/nvim"

run_inject() {
    local window_class="$1"
    local mode="${2:-}"
    PATH="$MOCK_BIN:$PATH" \
        MOCK_LOG="$MOCK_LOG" \
        XDG_STATE_HOME="$TEST_ROOT/state" \
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$TEST_ROOT}" \
        STT_EXPECTED_TEXT="dictated words" \
        "$SCRIPT_UNDER_TEST" "0xabc" "$window_class" "$mode" 2>/dev/null
}

generic_result=$(run_inject "firefox")
[[ "$generic_result" == '{"path":"paste","success":true,"downgraded":false,"submitted":false}' ]]
grep -qF 'dispatch sendshortcut CTRL, V, address:0xabc' "$MOCK_LOG"

: > "$MOCK_LOG"
terminal_result=$(run_inject "ghostty")
[[ "$terminal_result" == '{"path":"paste","success":true,"downgraded":false,"submitted":false}' ]]
grep -qF 'dispatch sendshortcut CTRL SHIFT, V, address:0xabc' "$MOCK_LOG"

: > "$MOCK_LOG"
submit_result=$(run_inject "firefox" "submit")
[[ "$submit_result" == '{"path":"paste","success":true,"downgraded":true,"submitted":false}' ]]
grep -qF 'dispatch sendshortcut CTRL, V, address:0xabc' "$MOCK_LOG"

: > "$MOCK_LOG"
python - "$TEST_ROOT/nvim.sock" <<'PY'
import socket
import sys

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.close()
PY
rpc_result=$(STT_NVIM_SOCKET="$TEST_ROOT/nvim.sock" STT_NVIM_ACTIVE_BUF=7 run_inject "ghostty" "submit")
[[ "$rpc_result" == '{"path":"rpc","success":true,"downgraded":false,"submitted":true}' ]]
[[ ! -s "$MOCK_LOG" ]]

: > "$MOCK_LOG"
python - "$TEST_ROOT/symmetria-ide-agents-42.sock" <<'PY' &
import json
import socket
import sys

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(sys.argv[1])
    server.listen(1)
    connection, _ = server.accept()
    with connection:
        reader = connection.makefile("r", encoding="utf-8")
        json.loads(reader.readline())
        connection.sendall(
            b'{"type":"stt_inject_result","ok":true,"submitted":true}\n'
        )
PY
ide_server_pid=$!
for _ in {1..100}; do
    [[ -S "$TEST_ROOT/symmetria-ide-agents-42.sock" ]] && break
    sleep 0.01
done
direct_result=$(
    XDG_RUNTIME_DIR="$TEST_ROOT" \
        STT_IDE_PID=42 \
        STT_IDE_BUF=3 \
        STT_RPC_ONLY=1 \
        run_inject "symmetria-ide" "submit"
)
wait "$ide_server_pid"
[[ "$direct_result" == '{"path":"direct","success":true,"downgraded":false,"submitted":true}' ]]
[[ ! -s "$MOCK_LOG" ]]

: > "$MOCK_LOG"
missing_result=$(MOCK_WINDOW_PRESENT=0 run_inject "firefox")
[[ "$missing_result" == '{"path":"none","success":false,"downgraded":false,"submitted":false}' ]]
[[ ! -s "$MOCK_LOG" ]]

printf 'stt-inject regression checks passed\n'
