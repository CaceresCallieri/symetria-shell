#!/usr/bin/env python3
"""Generate the eye-opening starting sprite sheet for ClaudeSparkle.

Reads the working sparkle sprite, extracts one frame (frame 0), and generates
a 15-frame sprite sheet using SVG <use> with scale transforms that create an
eye-opening + double-blink animation.

The approach: each frame shows the same starburst shape scaled differently
around the frame center. Vertical squishing creates a "closed eye" sliver;
full scale is the "open eye".

Usage: python3 scripts/generate-starting-sprite.py
"""

import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ASSETS_DIR = SCRIPT_DIR.parent / "assets"
WORKING_SPRITE = ASSETS_DIR / "claude-sparkle-sprite.svg"
OUTPUT_SPRITE = ASSETS_DIR / "claude-sparkle-starting-sprite.svg"

FRAME_SIZE = 100
CENTER = FRAME_SIZE / 2  # 50

# (xScale, yScale) for each of 15 frames.
# At 101ms/frame, total duration = 1515ms (~1.5s).
#
# Design: gentle emergence then subtle breathing.
#   Frames 0-8  (909ms): Slow emergence — seed to full starburst
#   Frames 9-14 (606ms): Subtle breathing pulse (full → 92% → full)
FRAMES = [
    (0.15, 0.10),  # 0:  Tiny seed
    (0.25, 0.18),  # 1:  Growing
    (0.36, 0.28),  # 2:  Opening
    (0.48, 0.40),  # 3:  More open
    (0.60, 0.53),  # 4:  Halfway
    (0.72, 0.66),  # 5:  Past halfway
    (0.83, 0.79),  # 6:  Nearly there
    (0.92, 0.90),  # 7:  Almost full
    (1.00, 1.00),  # 8:  Full
    (0.97, 0.96),  # 9:  Breathe out (slight shrink)
    (0.94, 0.92),  # 10: Breathe out (bottom)
    (0.97, 0.96),  # 11: Breathe in
    (1.00, 1.00),  # 12: Full
    (1.00, 1.00),  # 13: Hold
    (1.00, 1.00),  # 14: Final hold
]


def extract_frame0_path(svg_content: str) -> str:
    """Extract frame 0's path data from the working sprite sheet.

    Frame 0 is the first closed subpath — everything up to the first 'z' command.
    In SVG path syntax, 'z' is never part of coordinate values, so this is safe.
    """
    match = re.search(r'd="([^"]+)"', svg_content)
    if not match:
        raise ValueError("No path d attribute found in working sprite")
    full_path = match.group(1)

    # Find first closepath command (z or Z)
    for i, ch in enumerate(full_path):
        if ch in "zZ":
            return full_path[: i + 1]

    raise ValueError("No closepath (z/Z) found in working sprite path data")


def generate_sprite(base_path_d: str) -> str:
    """Generate the 15-frame starting sprite SVG.

    Uses <defs> + <use> with transform to avoid duplicating the path data 15 times.
    Each frame scales the base starburst around the center of its 100×100 slot.

    Transform chain (SVG reads right-to-left):
        translate(50, N*100+50) scale(sx, sy) translate(-50, -50)
    This centers the base shape at origin, scales it, then places it in frame N's slot.
    """
    num_frames = len(FRAMES)
    total_height = FRAME_SIZE * num_frames

    parts = []
    parts.append(f'<svg viewBox="0 0 {FRAME_SIZE} {total_height}">')
    parts.append(f'<defs><path id="s" d="{base_path_d}"/></defs>')

    for i, (sx, sy) in enumerate(FRAMES):
        y_off = i * FRAME_SIZE
        cy = y_off + CENTER

        if sx == 1.0 and sy == 1.0:
            # Identity scale — just translate to frame slot
            parts.append(f'<use href="#s" transform="translate(0,{y_off:.0f})"/>')
        else:
            # Scale around center of frame slot
            parts.append(
                f'<use href="#s" transform="translate({CENTER:.0f},{cy:.0f})'
                f" scale({sx},{sy})"
                f' translate(-{CENTER:.0f},-{CENTER:.0f})"/>'
            )

    parts.append("</svg>")
    return "".join(parts)


if __name__ == "__main__":
    svg_content = WORKING_SPRITE.read_text()
    frame0 = extract_frame0_path(svg_content)
    print(f"Extracted frame 0: {len(frame0)} chars")

    output = generate_sprite(frame0)
    OUTPUT_SPRITE.write_text(output)
    print(f"Generated {OUTPUT_SPRITE.name} ({len(output)} bytes, {len(FRAMES)} frames)")
