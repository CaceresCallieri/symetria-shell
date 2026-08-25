#!/usr/bin/env bash
# Run qmllint over every .qml file in the repository, using the policy in
# .qmllint.ini. Invoked by .github/workflows/lint.yml inside `nix develop`.
#
# This script exists because the previous inline version could not tell a
# missing tool from a real finding: it captured stderr into the same variable
# it tested for diagnostics, so `qmllint: command not found` read as a code
# defect and reported 408 identical false findings on every run for four
# months. Every guard below traces to one half of that failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SHADOW_TREE="build/qmllint"

# --- Resolve the tool ------------------------------------------------------
# Never guess and never continue without it. A missing tool is ONE tooling
# error, not a finding per file.
if ! QMLLINT="$(command -v qmllint 2>/dev/null)"; then
    echo "::error::qmllint not found on PATH. The devShell should provide it via qt6.qtdeclarative (see flake.nix)."
    exit 1
fi

# --- Assert it is the Qt6 tool ---------------------------------------------
# This guard is the whole reason the check was worthless. Distributions ship
# TWO binaries called qmllint: Qt 5.15's (package qt5-declarative on Arch,
# reporting "qmllint 1.0") and Qt 6's. The Qt5 one predates Quickshell's
# pragmas, exits 255 with no output on ~93% of this repo, and supports none of
# the warning categories in .qmllint.ini. If it wins the PATH lookup, the job
# passes while verifying nothing.
QMLLINT_VERSION="$("$QMLLINT" --version 2>&1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)"
QMLLINT_MAJOR="${QMLLINT_VERSION%%.*}"
if [[ -z "$QMLLINT_MAJOR" || "$QMLLINT_MAJOR" -lt 6 ]]; then
    echo "::error::$QMLLINT reports version '$QMLLINT_VERSION' — expected Qt 6 or newer. This is almost certainly Qt 5.15's qmllint, which cannot parse this codebase."
    exit 1
fi

# --- Assert the shadow tree exists -----------------------------------------
# Without it, `import qs.config` fails to resolve and the cascade inflates the
# findings roughly twelvefold. The categories in .qmllint.ini were calibrated
# WITH the tree present, so linting without it is not a stricter check — it is
# a differently-calibrated one that reports mostly noise.
if [[ ! -f "$SHADOW_TREE/qs/qmldir" ]]; then
    echo "::error::$SHADOW_TREE is missing or incomplete. Run ./scripts/gen-qmllint-tree.py first."
    exit 1
fi

# --- Diagnostics -----------------------------------------------------------
# Printed on every run, including green ones. The four-month outage persisted
# because the one step that would have exposed it ran `qmllint --version ||
# true` and went green on failure. Nothing here is allowed to fail silently.
echo "qmllint:  $QMLLINT (version $QMLLINT_VERSION)"
echo "policy:   $(realpath .qmllint.ini)"
echo "imports:  -I $SHADOW_TREE, plus QML_IMPORT_PATH via -E"
echo "QML_IMPORT_PATH=${QML_IMPORT_PATH:-<unset>}"
echo

# --- Lint ------------------------------------------------------------------
OUTPUT_LOG="$(mktemp)"
trap 'rm -f "$OUTPUT_LOG"' EXIT

TOTAL=0
FAILED=0
FAILED_FILES=()

while IFS= read -r -d '' file; do
    TOTAL=$((TOTAL + 1))

    # `-E` adds QML_IMPORT_PATH (Quickshell and the Symmetria plugin, supplied
    # by the devShell); `-I` adds the generated qs.* shadow tree.
    #
    # Capture stdout and stderr together, then branch on the EXIT CODE, never
    # on whether the output is non-empty. Findings at `info` level print text
    # and exit 0 by design, so a non-empty-output test would fail the build on
    # all 1,300 baseline findings.
    set +e
    output="$("$QMLLINT" -E -I "$SHADOW_TREE" "$file" 2>&1)"
    status=$?
    set -e

    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >>"$OUTPUT_LOG"
    fi

    if [[ $status -ne 0 ]]; then
        FAILED=$((FAILED + 1))
        FAILED_FILES+=("$file")
        echo "::group::qmllint FAILED — $file"
        printf '%s\n' "$output"
        echo "::endgroup::"
    fi
done < <(find . -name '*.qml' -not -path './.git/*' -not -path "./$SHADOW_TREE/*" -print0)

# --- Report ----------------------------------------------------------------
# The per-category tally is the maintenance signal for .qmllint.ini: when a
# category listed in its `info` block reaches zero here, promote it to `error`.
echo
echo "::group::qmllint findings by category (info-level findings do not fail the build)"
# The leading [a-z] is required, not cosmetic: qmllint echoes the offending
# source line, so a line ending in `clients[0]` would otherwise be tallied as a
# category named "0".
grep -oE '\[[a-z][a-z0-9.-]*\]$' "$OUTPUT_LOG" | sort | uniq -c | sort -rn || echo "(none)"
echo "::endgroup::"

echo
if [[ $FAILED -gt 0 ]]; then
    echo "::error::qmllint: $FAILED of $TOTAL file(s) produced error-level findings"
    printf '  %s\n' "${FAILED_FILES[@]}"
    exit 1
fi

echo "qmllint: $TOTAL file(s) passed — no error-level findings."
echo "Info-level findings above are the recorded backlog; see .qmllint.ini."
