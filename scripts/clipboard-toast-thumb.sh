#!/bin/bash
# Generate a thumbnail from the current clipboard image for toast notifications.
# Usage: clipboard-toast-thumb.sh <output_path>
#
# Reads clipboard via wl-paste, validates and resizes to 256x256 via PIL.
# Exit codes:
#   0 — success
#   1 — failure (not an image or processing error)

set -euo pipefail

for cmd in wl-paste python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: required command '$cmd' not found" >&2
        exit 1
    }
done

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <output_path>" >&2
    exit 1
fi

OUTPUT_PATH="$1"
DIR=$(dirname "$OUTPUT_PATH")
RAW="${OUTPUT_PATH}.raw"
TMP="${OUTPUT_PATH}.tmp"

cleanup() { rm -f "$RAW" "$TMP"; }
trap cleanup EXIT

mkdir -p "$DIR"
wl-paste > "$RAW" 2>/dev/null

# Validate and resize via PIL
python3 - "$RAW" "$TMP" << 'PYEOF'
import sys

raw_path = sys.argv[1]
tmp_path = sys.argv[2]

try:
    from PIL import Image

    img = Image.open(raw_path)
    img.load()
    img.thumbnail((256, 256), Image.LANCZOS)
    img.save(tmp_path, format="PNG")
except ImportError:
    # Pillow not installed — exit 1 so the caller shows icon-only toast
    print("NO_PILLOW: install python-pillow for image thumbnails", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"PIL error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Atomic rename
mv "$TMP" "$OUTPUT_PATH"
