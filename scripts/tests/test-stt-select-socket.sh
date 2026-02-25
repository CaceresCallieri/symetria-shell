#!/bin/bash
# Test harness for stt-select-socket.sh
#
# Validates the core logic: PID-scoped BFS search, socket filtering,
# focus verification, output format, and edge cases.
#
# Self-contained: creates mock environments in a temp directory and
# cleans up on exit. Uses PATH manipulation to intercept pgrep, nvim,
# timeout, and jq calls with controllable mock scripts.
#
# Usage: ./test-stt-select-socket.sh [-v]
#   -v  Verbose mode: show stdout/stderr from each test run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/stt-select-socket.sh"

# ── Globals ──────────────────────────────────────────────────────────────────

TMPDIR_ROOT=""
MOCK_BIN=""
MOCK_SOCKET_DIR=""
MOCK_CONFIG=""  # File that mock nvim reads to decide responses

PASS_COUNT=0
FAIL_COUNT=0
VERBOSE=false

[[ "${1:-}" == "-v" ]] && VERBOSE=true

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Setup / Teardown ────────────────────────────────────────────────────────

setup() {
    TMPDIR_ROOT=$(mktemp -d "/tmp/test-stt-select-socket.XXXXXX")
    MOCK_BIN="$TMPDIR_ROOT/mock-bin"
    MOCK_SOCKET_DIR="$TMPDIR_ROOT/run-user"
    MOCK_CONFIG="$TMPDIR_ROOT/mock-config"

    mkdir -p "$MOCK_BIN" "$MOCK_SOCKET_DIR"

    # ── Mock: id ──────────────────────────────────────────────────────────
    # The real script calls `id -u`; we redirect SOCKET_DIR via a mock id
    # that returns a UID matching our temp dir layout. But actually the
    # script constructs /run/user/$UID — we cannot create real unix sockets
    # there. Instead, we patch the script to use our SOCKET_DIR.
    #
    # Approach: We create a wrapper script that sets SOCKET_DIR before
    # sourcing the real script. But the real script is not source-friendly.
    #
    # Better approach: We create a modified copy that replaces the
    # SOCKET_DIR assignment.
    create_patched_script

    # ── Mock: pgrep ───────────────────────────────────────────────────────
    cat > "$MOCK_BIN/pgrep" << 'MOCK_PGREP'
#!/bin/bash
# Mock pgrep: reads "$MOCK_CONFIG.pgrep" for parent→children mappings.
# Format: one line per mapping: "parent_pid:child1 child2 child3"
# If -P <pid> is requested, find the line starting with "<pid>:" and
# output the children (one per line).
if [[ "$1" != "-P" ]]; then
    exec /usr/bin/pgrep "$@"
fi
PARENT_PID="$2"
CONFIG_FILE="${MOCK_CONFIG}.pgrep"
if [[ ! -f "$CONFIG_FILE" ]]; then
    exit 1
fi
while IFS=: read -r ppid children; do
    if [[ "$ppid" == "$PARENT_PID" ]]; then
        for child in $children; do
            echo "$child"
        done
        exit 0
    fi
done < "$CONFIG_FILE"
exit 1
MOCK_PGREP
    chmod +x "$MOCK_BIN/pgrep"

    # ── Mock: nvim ────────────────────────────────────────────────────────
    cat > "$MOCK_BIN/nvim" << 'MOCK_NVIM'
#!/bin/bash
# Mock nvim: reads "$MOCK_CONFIG.nvim" for socket→JSON response mappings.
# Format: one line per mapping: "socket_path|json_response"
# If --server <socket> --remote-expr ... is called, look up the socket.
SOCKET=""
for arg in "$@"; do
    if [[ "$prev" == "--server" ]]; then
        SOCKET="$arg"
    fi
    prev="$arg"
done

if [[ -z "$SOCKET" ]]; then
    exit 1
fi

CONFIG_FILE="${MOCK_CONFIG}.nvim"
if [[ ! -f "$CONFIG_FILE" ]]; then
    exit 1
fi

while IFS='|' read -r sock_path json_response; do
    if [[ "$sock_path" == "$SOCKET" ]]; then
        echo "$json_response"
        exit 0
    fi
done < "$CONFIG_FILE"
exit 1
MOCK_NVIM
    chmod +x "$MOCK_BIN/nvim"

    # ── Mock: timeout ─────────────────────────────────────────────────────
    # The real script calls `timeout 1s nvim ...`; just strip the timeout
    # prefix and pass through to our mock nvim (already in PATH).
    cat > "$MOCK_BIN/timeout" << 'MOCK_TIMEOUT'
#!/bin/bash
# Mock timeout: skip the duration arg, exec the rest
shift  # remove "1s" (or whatever duration)
exec "$@"
MOCK_TIMEOUT
    chmod +x "$MOCK_BIN/timeout"

    # ── Mock: id ──────────────────────────────────────────────────────────
    # Not needed since we patch the script directly.

    # ── Mock: jq ──────────────────────────────────────────────────────────
    # Use the real jq — it is a pure data transformer with no side effects.
    # Just ensure it is available.
    if ! command -v jq &>/dev/null; then
        echo "FATAL: jq is required to run these tests" >&2
        exit 1
    fi
}

teardown() {
    if [[ -n "$TMPDIR_ROOT" && -d "$TMPDIR_ROOT" ]]; then
        rm -rf "$TMPDIR_ROOT"
    fi
}

trap teardown EXIT

# ── Patched Script ──────────────────────────────────────────────────────────

create_patched_script() {
    # Create a copy of the script under test with SOCKET_DIR pointing
    # to our mock directory. We replace the line that sets SOCKET_DIR.
    local patched="$TMPDIR_ROOT/stt-select-socket-patched.sh"
    sed "s|SOCKET_DIR=\"/run/user/\$USER_ID\"|SOCKET_DIR=\"$MOCK_SOCKET_DIR\"|" \
        "$SCRIPT_UNDER_TEST" > "$patched"
    chmod +x "$patched"
}

# ── Helpers ─────────────────────────────────────────────────────────────────

# Create a mock Unix socket at the given path.
# Uses a background socat listener to create a real Unix domain socket.
create_mock_socket() {
    local path="$1"
    # Python one-liner to bind a Unix socket, then immediately close the
    # listener. The socket file remains as type "socket" in the filesystem.
    python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
s.close()
" "$path"
}

# Configure pgrep mock: parent_pid → list of child pids
# Can be called multiple times to add multiple parent entries.
configure_pgrep() {
    local parent_pid="$1"
    shift
    local children="$*"
    echo "${parent_pid}:${children}" >> "$MOCK_CONFIG.pgrep"
}

# Configure nvim mock: socket_path → JSON response
configure_nvim_response() {
    local socket_path="$1"
    local json="$2"
    echo "${socket_path}|${json}" >> "$MOCK_CONFIG.nvim"
}

# Clear all mock configurations (call between tests).
clear_mocks() {
    rm -f "$MOCK_CONFIG.pgrep" "$MOCK_CONFIG.nvim"
    rm -f "$MOCK_SOCKET_DIR"/nvim.*.0
    # Recreate empty config files
    touch "$MOCK_CONFIG.pgrep" "$MOCK_CONFIG.nvim"
}

# Run the patched script with the given arguments.
# Sets PATH so our mocks are found first.
# Exports MOCK_CONFIG so mock scripts can find their config files.
# Returns: sets LAST_STDOUT, LAST_STDERR, LAST_EXIT
run_script() {
    local patched="$TMPDIR_ROOT/stt-select-socket-patched.sh"
    local stdout_file="$TMPDIR_ROOT/stdout"
    local stderr_file="$TMPDIR_ROOT/stderr"

    LAST_EXIT=0
    LAST_STDOUT=""
    LAST_STDERR=""

    env PATH="$MOCK_BIN:$PATH" \
        MOCK_CONFIG="$MOCK_CONFIG" \
        bash "$patched" "$@" \
        >"$stdout_file" 2>"$stderr_file" || LAST_EXIT=$?

    LAST_STDOUT=$(cat "$stdout_file")
    LAST_STDERR=$(cat "$stderr_file")

    if $VERBOSE; then
        echo "  [stdout] $(cat "$stdout_file")"
        echo "  [stderr] $(cat "$stderr_file")"
        echo "  [exit]   $LAST_EXIT"
    fi
}

# ── Assertions ──────────────────────────────────────────────────────────────

assert_stdout_empty() {
    if [[ -n "$LAST_STDOUT" ]]; then
        echo -e "    ${RED}ASSERT FAIL: expected empty stdout, got: '$LAST_STDOUT'${RESET}" >&2
        return 1
    fi
}

assert_stdout_equals() {
    local expected="$1"
    if [[ "$LAST_STDOUT" != "$expected" ]]; then
        echo -e "    ${RED}ASSERT FAIL: stdout mismatch${RESET}" >&2
        echo "      expected: $(printf '%q' "$expected")" >&2
        echo "      actual:   $(printf '%q' "$LAST_STDOUT")" >&2
        return 1
    fi
}

assert_stdout_contains() {
    local needle="$1"
    if [[ "$LAST_STDOUT" != *"$needle"* ]]; then
        echo -e "    ${RED}ASSERT FAIL: stdout does not contain '$needle'${RESET}" >&2
        echo "      stdout: '$LAST_STDOUT'" >&2
        return 1
    fi
}

assert_stderr_contains() {
    local needle="$1"
    if [[ "$LAST_STDERR" != *"$needle"* ]]; then
        echo -e "    ${RED}ASSERT FAIL: stderr does not contain '$needle'${RESET}" >&2
        echo "      stderr: '$LAST_STDERR'" >&2
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    if [[ "$LAST_EXIT" -ne "$expected" ]]; then
        echo -e "    ${RED}ASSERT FAIL: exit code $LAST_EXIT, expected $expected${RESET}" >&2
        return 1
    fi
}

assert_field_count() {
    local expected_count="$1"
    local actual_count
    actual_count=$(echo "$LAST_STDOUT" | awk -F'\t' '{print NF}')
    if [[ "$actual_count" -ne "$expected_count" ]]; then
        echo -e "    ${RED}ASSERT FAIL: expected $expected_count tab-delimited fields, got $actual_count${RESET}" >&2
        echo "      stdout: '$LAST_STDOUT'" >&2
        return 1
    fi
}

# ── Test Runner ─────────────────────────────────────────────────────────────

run_test() {
    local test_name="$1"
    local test_func="$2"

    clear_mocks

    echo -en "  ${CYAN}$test_name${RESET} ... "

    local result=0
    $test_func || result=$?

    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}PASS${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}FAIL${RESET}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── Test Cases ──────────────────────────────────────────────────────────────

test_no_sockets_exist() {
    # No socket files in the directory at all.
    # Script should exit cleanly with no output.
    run_script 0

    assert_exit_code 0 &&
    assert_stdout_empty
}

test_no_sockets_for_pid() {
    # A PID is given but no descendant has a matching socket file.
    configure_pgrep 1000 1001 1002

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty
}

test_single_socket_focused() {
    # One socket, has_instances=true, has_focus=true.
    # Should output the socket info in tab-delimited format.
    local sock="$MOCK_SOCKET_DIR/nvim.5001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 5001
    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":3,"instance_title":"test.qml","instance_cwd":"/home/user/project"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_equals "$(printf '%s\t%s\t%s\t%s' "$sock" "3" "test.qml" "/home/user/project")" &&
    assert_field_count 4
}

test_single_socket_not_focused() {
    # One socket, has_instances=true, has_focus=false.
    # Should output nothing (focus check fails).
    local sock="$MOCK_SOCKET_DIR/nvim.5001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 5001
    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":false,"last_active_buf":3,"instance_title":"test.qml","instance_cwd":"/home/user/project"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty &&
    assert_stderr_contains "no socket matched"
}

test_single_socket_no_instances() {
    # One socket, has_instances=false, has_focus=true.
    # Should output nothing (instance check fails).
    local sock="$MOCK_SOCKET_DIR/nvim.5001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 5001
    configure_nvim_response "$sock" \
        '{"has_instances":false,"has_focus":true,"last_active_buf":1,"instance_title":"","instance_cwd":""}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty &&
    assert_stderr_contains "no socket matched"
}

test_multiple_sockets_one_focused() {
    # Two sockets, only one has focus. Should output the focused one.
    local sock1="$MOCK_SOCKET_DIR/nvim.5001.0"
    local sock2="$MOCK_SOCKET_DIR/nvim.5002.0"
    create_mock_socket "$sock1"
    create_mock_socket "$sock2"

    configure_pgrep 1000 5001 5002
    configure_nvim_response "$sock1" \
        '{"has_instances":true,"has_focus":false,"last_active_buf":1,"instance_title":"unfocused.qml","instance_cwd":"/home/user/a"}'
    configure_nvim_response "$sock2" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":7,"instance_title":"focused.qml","instance_cwd":"/home/user/b"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_equals "$(printf '%s\t%s\t%s\t%s' "$sock2" "7" "focused.qml" "/home/user/b")" &&
    assert_field_count 4
}

test_multiple_sockets_multiple_focused() {
    # Two sockets, both focused. Ambiguous case — should output nothing.
    local sock1="$MOCK_SOCKET_DIR/nvim.5001.0"
    local sock2="$MOCK_SOCKET_DIR/nvim.5002.0"
    create_mock_socket "$sock1"
    create_mock_socket "$sock2"

    configure_pgrep 1000 5001 5002
    configure_nvim_response "$sock1" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":1,"instance_title":"a.qml","instance_cwd":"/home/user/a"}'
    configure_nvim_response "$sock2" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":2,"instance_title":"b.qml","instance_cwd":"/home/user/b"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty &&
    assert_stderr_contains "ambiguous" &&
    assert_stderr_contains "2 sockets matched"
}

test_pid_scoped_bfs_descendants() {
    # Window PID 1000 → child 2000 → grandchild 3000.
    # Only grandchild 3000 has a socket. Verify BFS finds it.
    local sock="$MOCK_SOCKET_DIR/nvim.3000.0"
    create_mock_socket "$sock"

    # PID tree: 1000 → 2000 → 3000 (nvim)
    configure_pgrep 1000 2000
    configure_pgrep 2000 3000

    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":42,"instance_title":"deep.lua","instance_cwd":"/home/user/deep"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_equals "$(printf '%s\t%s\t%s\t%s' "$sock" "42" "deep.lua" "/home/user/deep")" &&
    assert_field_count 4
}

test_pid_scoped_ignores_unrelated() {
    # Window PID 1000 → child 2000 (no socket).
    # An unrelated PID 9999 has a socket, but it should NOT be considered.
    local unrelated_sock="$MOCK_SOCKET_DIR/nvim.9999.0"
    create_mock_socket "$unrelated_sock"

    configure_pgrep 1000 2000
    # No socket for PID 2000, and PID 9999 is not a descendant of 1000

    configure_nvim_response "$unrelated_sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":1,"instance_title":"rogue.txt","instance_cwd":"/tmp"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty
}

test_no_pid_backward_compat() {
    # No PID given (or PID=0): should scan all sockets globally.
    local sock1="$MOCK_SOCKET_DIR/nvim.7001.0"
    local sock2="$MOCK_SOCKET_DIR/nvim.7002.0"
    create_mock_socket "$sock1"
    create_mock_socket "$sock2"

    # Only sock1 is focused
    configure_nvim_response "$sock1" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":10,"instance_title":"global.py","instance_cwd":"/home/user/global"}'
    configure_nvim_response "$sock2" \
        '{"has_instances":true,"has_focus":false,"last_active_buf":20,"instance_title":"other.py","instance_cwd":"/home/user/other"}'

    # Pass 0 explicitly for backward compat
    run_script 0

    assert_exit_code 0 &&
    assert_stdout_equals "$(printf '%s\t%s\t%s\t%s' "$sock1" "10" "global.py" "/home/user/global")" &&
    assert_field_count 4
}

test_no_pid_omitted() {
    # No argument at all: same as PID=0, scans all sockets.
    local sock="$MOCK_SOCKET_DIR/nvim.8001.0"
    create_mock_socket "$sock"

    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":5,"instance_title":"noarg.rs","instance_cwd":"/home/user/noarg"}'

    # No argument
    run_script

    assert_exit_code 0 &&
    assert_stdout_equals "$(printf '%s\t%s\t%s\t%s' "$sock" "5" "noarg.rs" "/home/user/noarg")" &&
    assert_field_count 4
}

test_output_format_tab_delimited() {
    # Verify the output is exactly 4 fields separated by literal tabs,
    # with no trailing newline.
    local sock="$MOCK_SOCKET_DIR/nvim.6001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 6001
    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":99,"instance_title":"My Project Title","instance_cwd":"/home/user/my project dir"}'

    run_script 1000

    assert_exit_code 0

    # Verify tab count (should be exactly 3 tabs for 4 fields)
    local tab_count
    tab_count=$(printf '%s' "$LAST_STDOUT" | tr -cd '\t' | wc -c)
    if [[ "$tab_count" -ne 3 ]]; then
        echo -e "    ${RED}ASSERT FAIL: expected 3 tabs, got $tab_count${RESET}" >&2
        return 1
    fi

    # Verify no trailing newline in printf output
    local byte_count_with_newline
    local byte_count_without
    byte_count_with_newline=$(echo "$LAST_STDOUT" | wc -c)
    byte_count_without=$(printf '%s' "$LAST_STDOUT" | wc -c)
    if [[ "$byte_count_with_newline" -ne $((byte_count_without + 1)) ]]; then
        echo -e "    ${RED}ASSERT FAIL: unexpected trailing content in output${RESET}" >&2
        return 1
    fi

    # Verify individual fields
    local f_sock f_buf f_title f_cwd
    IFS=$'\t' read -r f_sock f_buf f_title f_cwd <<< "$LAST_STDOUT"

    if [[ "$f_sock" != "$sock" ]]; then
        echo -e "    ${RED}ASSERT FAIL: socket field mismatch: '$f_sock' vs '$sock'${RESET}" >&2
        return 1
    fi
    if [[ "$f_buf" != "99" ]]; then
        echo -e "    ${RED}ASSERT FAIL: buf field mismatch: '$f_buf' vs '99'${RESET}" >&2
        return 1
    fi
    if [[ "$f_title" != "My Project Title" ]]; then
        echo -e "    ${RED}ASSERT FAIL: title field mismatch: '$f_title' vs 'My Project Title'${RESET}" >&2
        return 1
    fi
    if [[ "$f_cwd" != "/home/user/my project dir" ]]; then
        echo -e "    ${RED}ASSERT FAIL: cwd field mismatch: '$f_cwd' vs '/home/user/my project dir'${RESET}" >&2
        return 1
    fi
}

test_nvim_server_unreachable() {
    # Socket exists but nvim mock returns failure (simulating timeout/crash).
    local sock="$MOCK_SOCKET_DIR/nvim.5001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 5001
    # No nvim response configured → mock exits 1

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty
}

test_nvim_returns_invalid_json() {
    # Socket exists, nvim returns something that is not valid JSON.
    local sock="$MOCK_SOCKET_DIR/nvim.5001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 5001
    configure_nvim_response "$sock" "not valid json at all"

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_empty
}

test_null_fields_in_json() {
    # JSON has null for optional fields; jq defaults should apply.
    local sock="$MOCK_SOCKET_DIR/nvim.5001.0"
    create_mock_socket "$sock"

    configure_pgrep 1000 5001
    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":null,"instance_title":null,"instance_cwd":null}'

    run_script 1000

    assert_exit_code 0 &&
    # Should still output something with defaults for null fields
    assert_stdout_contains "$sock" &&
    assert_field_count 4

    # Verify the null fields resolved to defaults (-1 for buf, empty for title/cwd)
    local f_sock f_buf f_title f_cwd
    IFS=$'\t' read -r f_sock f_buf f_title f_cwd <<< "$LAST_STDOUT"
    if [[ "$f_buf" != "-1" ]]; then
        echo -e "    ${RED}ASSERT FAIL: null buf should default to -1, got '$f_buf'${RESET}" >&2
        return 1
    fi
}

test_deep_bfs_three_levels() {
    # Verify BFS goes at least 3 levels deep:
    # PID 100 → 200 → 300 → 400 (nvim)
    local sock="$MOCK_SOCKET_DIR/nvim.400.0"
    create_mock_socket "$sock"

    configure_pgrep 100 200
    configure_pgrep 200 300
    configure_pgrep 300 400

    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":1,"instance_title":"deep3.vim","instance_cwd":"/deep"}'

    run_script 100

    assert_exit_code 0 &&
    assert_stdout_contains "$sock"
}

test_window_pid_itself_has_socket() {
    # The window PID itself is also an nvim process.
    # BFS includes the root PID in descendants, so it should be found.
    local sock="$MOCK_SOCKET_DIR/nvim.1000.0"
    create_mock_socket "$sock"

    # No children, but PID 1000 itself has a socket
    configure_nvim_response "$sock" \
        '{"has_instances":true,"has_focus":true,"last_active_buf":1,"instance_title":"self.vim","instance_cwd":"/self"}'

    run_script 1000

    assert_exit_code 0 &&
    assert_stdout_contains "$sock"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}Test harness: stt-select-socket.sh${RESET}"
    echo -e "Script under test: ${YELLOW}$SCRIPT_UNDER_TEST${RESET}"
    echo ""

    setup

    echo -e "${BOLD}Core behavior:${RESET}"
    run_test "No sockets exist"                       test_no_sockets_exist
    run_test "No sockets for given PID descendants"   test_no_sockets_for_pid
    run_test "Single socket, focused"                 test_single_socket_focused
    run_test "Single socket, not focused"             test_single_socket_not_focused
    run_test "Single socket, no instances"            test_single_socket_no_instances

    echo ""
    echo -e "${BOLD}Multiple sockets:${RESET}"
    run_test "Multiple sockets, exactly one focused"  test_multiple_sockets_one_focused
    run_test "Multiple sockets, ambiguous (both focused)" test_multiple_sockets_multiple_focused

    echo ""
    echo -e "${BOLD}PID-scoped BFS search:${RESET}"
    run_test "BFS finds grandchild socket"            test_pid_scoped_bfs_descendants
    run_test "BFS ignores unrelated PID sockets"      test_pid_scoped_ignores_unrelated
    run_test "BFS 3 levels deep"                      test_deep_bfs_three_levels
    run_test "Window PID itself has socket"            test_window_pid_itself_has_socket

    echo ""
    echo -e "${BOLD}Backward compatibility (no PID):${RESET}"
    run_test "PID=0 scans all sockets"                test_no_pid_backward_compat
    run_test "No argument scans all sockets"          test_no_pid_omitted

    echo ""
    echo -e "${BOLD}Output format:${RESET}"
    run_test "Tab-delimited 4-field format"           test_output_format_tab_delimited

    echo ""
    echo -e "${BOLD}Error resilience:${RESET}"
    run_test "Nvim server unreachable"                test_nvim_server_unreachable
    run_test "Nvim returns invalid JSON"              test_nvim_returns_invalid_json
    run_test "Null fields in JSON use defaults"       test_null_fields_in_json

    # ── Summary ───────────────────────────────────────────────────────────
    echo ""
    echo "─────────────────────────────────────"
    local total=$((PASS_COUNT + FAIL_COUNT))
    echo -e "${BOLD}Results: $total tests${RESET}"
    echo -e "  ${GREEN}Passed: $PASS_COUNT${RESET}"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "  ${RED}Failed: $FAIL_COUNT${RESET}"
    else
        echo -e "  Failed: 0"
    fi
    echo "─────────────────────────────────────"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "\n${RED}${BOLD}FAILED${RESET}"
        exit 1
    else
        echo -e "\n${GREEN}${BOLD}ALL TESTS PASSED${RESET}"
        exit 0
    fi
}

main "$@"
