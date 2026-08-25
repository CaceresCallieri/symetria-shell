#!/usr/bin/env bash
# Check that tracked .qml files match qmlformat's output.
#
# Usage:
#   run-qmlformat.sh                 # every tracked .qml file
#   run-qmlformat.sh <file>...       # only the named files
#
# WHY THIS IS A SCRIPT AND NOT THE ONE-LINER
#
# The obvious form of this gate is:
#
#     qmlformat "$f" | diff -u "$f" -
#
# On this codebase that is unsound. qmlformat fails on 10 of 408 files by
# exiting 1 with ZERO bytes of output and NO diagnostic on stderr. Piped into
# diff, empty output reads as "every line was deleted", so the gate reports a
# crashed tool as a formatting violation — the same defect that made the old
# Lint workflow report a missing binary as 408 code findings.
#
# So this script branches on qmlformat's EXIT CODE first and only diffs output
# it actually produced. A file qmlformat cannot process is reported as a tooling
# failure and excluded from the verdict, per the catalog rule that a check which
# cannot run must never gate a review.
#
# One minimal trigger is confirmed — declaring a property named `id`:
#
#     import QtQuick
#     QtObject { readonly property string id: "x" }   // qmlformat: exit 1, no output
#
# That is legal QML: qmllint accepts it and the shell runs it. It accounts for
# services/Notifs.qml and modules/controlcenter/PaneRegistry.qml. The other
# eight files fail for reasons not yet isolated.
#
# EXPIRY: QTBUG-144943 (fix version 6.14) rewrites qmlformat from the DOM onto
# the AST, so both the failure set and the formatting output are expected to
# change on that upgrade. Re-run this script over the whole repo after any Qt
# minor bump and reformat if the output moved.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Absolute path, never the bare name: /usr/bin/qmlformat is Qt 5.15's tool.
# Same trap as qmllint — see docs/qmllint-setup.md.
QMLFORMAT=/usr/lib/qt6/bin/qmlformat
if ! command -v "$QMLFORMAT" >/dev/null 2>&1; then
    if ! QMLFORMAT="$(command -v qmlformat 2>/dev/null)"; then
        echo "::error::qmlformat not found. Expected /usr/lib/qt6/bin/qmlformat (package qt6-declarative)."
        exit 1
    fi
fi

QMLFORMAT_VERSION="$("$QMLFORMAT" --version 2>&1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)"
if [[ -z "${QMLFORMAT_VERSION%%.*}" || "${QMLFORMAT_VERSION%%.*}" -lt 6 ]]; then
    echo "::error::$QMLFORMAT reports version '$QMLFORMAT_VERSION' — expected Qt 6 or newer."
    exit 1
fi

echo "qmlformat: $QMLFORMAT (version $QMLFORMAT_VERSION)"
echo

FORMATTED=()
UNFORMATTED=()
UNPROCESSABLE=()

check_one() {
    local file="$1" output status
    set +e
    output="$("$QMLFORMAT" "$file" 2>/dev/null)"
    status=$?
    set -e

    # A non-zero exit OR empty output means qmlformat could not process the
    # file. Never diff that — empty output would present as a full-file
    # deletion. Note the emptiness test is a guard, not the primary signal:
    # some qmlformat failures still exit 0.
    if [[ $status -ne 0 || -z "$output" ]]; then
        UNPROCESSABLE+=("$file")
        return 0
    fi

    if printf '%s\n' "$output" | diff -q "$file" - >/dev/null 2>&1; then
        FORMATTED+=("$file")
    else
        UNFORMATTED+=("$file")
        echo "::group::qmlformat differs — $file"
        printf '%s\n' "$output" | diff -u "$file" - || true
        echo "::endgroup::"
    fi
}

if [[ $# -gt 0 ]]; then
    for file in "$@"; do
        [[ "$file" == *.qml ]] || continue
        [[ -f "$file" ]] || continue
        check_one "$file"
    done
else
    while IFS= read -r -d '' file; do
        check_one "$file"
    done < <(git ls-files -z '*.qml')
fi

if [[ ${#UNPROCESSABLE[@]} -gt 0 ]]; then
    echo
    echo "::group::qmlformat could not process ${#UNPROCESSABLE[@]} file(s) — tooling failure, not a finding"
    printf '  %s\n' "${UNPROCESSABLE[@]}"
    echo "::endgroup::"
fi

echo
if [[ ${#UNFORMATTED[@]} -gt 0 ]]; then
    echo "::error::qmlformat: ${#UNFORMATTED[@]} file(s) differ from formatted output"
    printf '  %s\n' "${UNFORMATTED[@]}"
    echo "Reformat them with: $QMLFORMAT -i <file>"
    exit 1
fi

echo "qmlformat: ${#FORMATTED[@]} file(s) formatted, ${#UNPROCESSABLE[@]} skipped as unprocessable."
