#!/usr/bin/env bash
# check-qml-conflicts.sh - Detect QML type name collisions in shell.qml imports
#
# QML resolves type name conflicts by using the LAST import. This can cause
# catastrophic silent failures where entire modules are replaced.
#
# Usage: ./scripts/check-qml-conflicts.sh [shell.qml path]
#
# Exit codes:
#   0 - No conflicts found
#   1 - Conflicts detected (lists them)
#   2 - Script error

set -eo pipefail

SHELL_QML="${1:-shell.qml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ ! -f "$ROOT_DIR/$SHELL_QML" ]]; then
    echo "Error: $SHELL_QML not found in $ROOT_DIR" >&2
    exit 2
fi

# Extract directory imports from shell.qml (e.g., import "modules/background")
# Ignores qualified imports (import Foo.Bar) and aliased imports
mapfile -t IMPORTS < <(
    grep -oP 'import\s+"\K[^"]+' "$ROOT_DIR/$SHELL_QML" 2>/dev/null || true
)

if [[ ${#IMPORTS[@]} -eq 0 ]]; then
    echo "No directory imports found in $SHELL_QML"
    exit 0
fi

# Extract type instantiations from shell.qml (e.g., "Background {}" -> "Background")
# Matches: TypeName { or TypeName{
USED_TYPES=()
while IFS= read -r type; do
    [[ -n "$type" ]] && USED_TYPES+=("$type")
done < <(grep -oP '^\s*\K[A-Z][A-Za-z0-9_]*(?=\s*\{)' "$ROOT_DIR/$SHELL_QML" 2>/dev/null | sort -u || true)

# Collect all .qml files from imported directories
declare -A TYPE_SOURCES  # type_name -> "path1:path2:..."
CONFLICTS=()
USED_CONFLICTS=()

for import_path in "${IMPORTS[@]}"; do
    dir="$ROOT_DIR/$import_path"
    if [[ ! -d "$dir" ]]; then
        continue
    fi

    # List .qml files (type names are filename without .qml)
    for qml_file in "$dir"/*.qml; do
        [[ -f "$qml_file" ]] || continue
        type_name="$(basename "$qml_file" .qml)"

        if [[ -n "${TYPE_SOURCES[$type_name]:-}" ]]; then
            # Conflict detected - type already defined elsewhere
            TYPE_SOURCES[$type_name]="${TYPE_SOURCES[$type_name]}:$import_path"
        else
            TYPE_SOURCES[$type_name]="$import_path"
        fi
    done
done

# Find types defined in multiple imports
for type_name in "${!TYPE_SOURCES[@]}"; do
    sources="${TYPE_SOURCES[$type_name]}"
    if [[ "$sources" == *:* ]]; then
        CONFLICTS+=("$type_name")
        # Check if this type is actually used in shell.qml
        if [[ ${#USED_TYPES[@]} -gt 0 ]]; then
            for used in "${USED_TYPES[@]}"; do
                if [[ "$used" == "$type_name" ]]; then
                    USED_CONFLICTS+=("$type_name")
                    break
                fi
            done
        fi
    fi
done

# Report results
if [[ ${#CONFLICTS[@]} -eq 0 ]]; then
    echo "✓ No QML type name conflicts detected"
    exit 0
fi

has_critical=false

if [[ ${#USED_CONFLICTS[@]} -gt 0 ]]; then
    has_critical=true
    echo "❌ CRITICAL: QML Type Conflicts in shell.qml!"
    echo ""
    echo "These types are BOTH conflicting AND instantiated in shell.qml."
    echo "The wrong component will be used, causing silent failures!"
    echo ""

    for type_name in "${USED_CONFLICTS[@]}"; do
        sources="${TYPE_SOURCES[$type_name]}"
        echo "  $type_name {}  ← USED IN shell.qml"
        IFS=':' read -ra paths <<< "$sources"
        for i in "${!paths[@]}"; do
            if [[ $i -eq $((${#paths[@]} - 1)) ]]; then
                echo "    → ${paths[$i]}/$type_name.qml  ← WINS (last import)"
            else
                echo "    ✗ ${paths[$i]}/$type_name.qml  ← SHADOWED!"
            fi
        done
        echo ""
    done
fi

# Report non-critical conflicts (types not used in shell.qml)
other_conflicts=()
for conflict in "${CONFLICTS[@]}"; do
    is_used=false
    if [[ ${#USED_CONFLICTS[@]} -gt 0 ]]; then
        for used in "${USED_CONFLICTS[@]}"; do
            [[ "$conflict" == "$used" ]] && is_used=true && break
        done
    fi
    $is_used || other_conflicts+=("$conflict")
done

if [[ ${#other_conflicts[@]} -gt 0 ]]; then
    echo "⚠️  Warning: Potential conflicts (not currently used in shell.qml)"
    echo ""
    for type_name in "${other_conflicts[@]}"; do
        sources="${TYPE_SOURCES[$type_name]}"
        echo "  $type_name.qml:"
        IFS=':' read -ra paths <<< "$sources"
        for i in "${!paths[@]}"; do
            if [[ $i -eq $((${#paths[@]} - 1)) ]]; then
                echo "    → ${paths[$i]}  ← would win"
            else
                echo "    ✗ ${paths[$i]}  ← would be shadowed"
            fi
        done
    done
    echo ""
fi

echo "Fix: Rename conflicting files with module prefix (e.g., Background.qml → ModuleNameBackground.qml)"

if $has_critical; then
    exit 1
else
    exit 0  # Warnings only, no critical issues
fi
