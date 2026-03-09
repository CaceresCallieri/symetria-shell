#!/bin/bash
# Decode a clipboard image entry, validate integrity, and produce a thumbnail.
# Usage: cliphist-decode-image.sh <entry_id> <output_path>
#
# Exit codes:
#   0 — success (file size printed to stdout)
#   1 — decode/processing failure
#   2 — truncated image detected and skipped
#
# Truncated PNGs are common with Wayland clipboard — if the source app closes
# before the clipboard transfer completes, cliphist stores a partial image.
# We detect these and skip them rather than showing black-filled placeholders.

set -euo pipefail

ENTRY_ID="$1"
OUTPUT_PATH="$2"
DIR=$(dirname "$OUTPUT_PATH")
RAW="${OUTPUT_PATH}.raw"
TMP="${OUTPUT_PATH}.tmp"

cleanup() { rm -f "$RAW" "$TMP"; }
trap cleanup EXIT

mkdir -p "$DIR"
cliphist decode "$ENTRY_ID" > "$RAW"

# Validate and resize via PIL.
# Tries loading WITHOUT LOAD_TRUNCATED_IMAGES first — if that fails,
# the image is truncated and we skip it (exit 2).
# Falls back to raw copy if Pillow is not installed.
python3 - "$RAW" "$TMP" << 'PYEOF'
import sys

raw_path = sys.argv[1]
tmp_path = sys.argv[2]

try:
    from PIL import Image, ImageFile

    # First pass: strict load (detects truncated images)
    try:
        img = Image.open(raw_path)
        img.load()
    except Exception:
        # Image is truncated — skip it
        print("TRUNCATED", file=sys.stderr)
        sys.exit(2)

    # Image is valid — resize and save
    img.thumbnail((512, 512), Image.LANCZOS)
    img.save(tmp_path, format="PNG")
except ImportError:
    # Pillow not installed — copy raw (truncated PNGs will fail in Qt)
    import shutil
    shutil.copy2(raw_path, tmp_path)
    print("NO_PILLOW", file=sys.stderr)
except Exception as e:
    print(f"PIL error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Atomic rename + output file size
mv "$TMP" "$OUTPUT_PATH"
stat -c %s "$OUTPUT_PATH"
