#!/usr/bin/env bash
# Run shellcheck over every .sh file in the repository.
# Invoked by .github/workflows/lint.yml inside `nix develop`.
#
# It runs under Nix, not against the runner's preinstalled shellcheck, because
# the preinstalled one drifts. ubuntu-latest shipped 0.9.0 while developers ran
# 0.11.0, and the two disagreed on this repository in both directions:
#
#   - SC2317 was renamed SC2329. The repo excluded SC2329, which 0.9.0 does not
#     know, so the exclusion silently did not apply on the runner and
#     scripts/tests/test-stt-select-socket.sh reported ~20 findings.
#   - 0.9.0 raises SC2015 on `A && B || true`; 0.11.0 does not, because a `C`
#     of `true` cannot misfire. Four sites tripped it.
#
# All of that was invisible for four months: shellcheck was the LAST step of a
# job whose qmllint step already exited 1, so it never executed once.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if ! SHELLCHECK="$(command -v shellcheck 2>/dev/null)"; then
    echo "::error::shellcheck not found on PATH. The devShell should provide it (see flake.nix)."
    exit 1
fi

# Printed on every run, green ones included. The version is the single most
# useful fact when a finding reproduces in CI but not locally.
echo "shellcheck: $SHELLCHECK"
"$SHELLCHECK" --version
echo

# SC2317/SC2329 are the same check ("function never invoked") under the old and
# new identifiers. Both are listed so the exclusion survives a version bump in
# either direction. It exists because this repo dispatches functions
# dynamically, which shellcheck cannot trace.
EXCLUDE="SC2317,SC2329"

ERRORS=0
FAILED_FILES=()
TOTAL=0

while IFS= read -r -d '' file; do
    TOTAL=$((TOTAL + 1))
    if ! "$SHELLCHECK" -e "$EXCLUDE" "$file"; then
        ERRORS=$((ERRORS + 1))
        FAILED_FILES+=("$file")
    fi
done < <(find . -name '*.sh' -not -path './.git/*' -not -path './build/*' -print0)

echo
if [[ $ERRORS -gt 0 ]]; then
    echo "::error::shellcheck: $ERRORS of $TOTAL file(s) failed"
    printf '  %s\n' "${FAILED_FILES[@]}"
    exit 1
fi

echo "shellcheck: $TOTAL file(s) passed."
