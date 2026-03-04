#!/usr/bin/env python3
"""Generate the stopping/collapse sprite sheet for ClaudeSparkle.

Reads the working sparkle sprite, extracts one frame (frame 0), and generates
a 12-frame sprite sheet using SVG <use> with scale transforms that create a
full-starburst-to-tiny-dot collapse animation.

This is the inverse of the starting emergence: the starburst settles briefly
at full size, then collapses to a small dormant dot and holds there.

Usage: python3 scripts/generate-stopping-sprite.py
"""

import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ASSETS_DIR = SCRIPT_DIR.parent / "assets"
WORKING_SPRITE = ASSETS_DIR / "claude-sparkle-sprite.svg"
OUTPUT_SPRITE = ASSETS_DIR / "claude-sparkle-stopping-sprite.svg"

FRAME_SIZE = 100
CENTER = FRAME_SIZE / 2  # 50

# (xScale, yScale) for each of 12 frames.
# At 152ms/frame (slower tick than working/thinking for a more deliberate feel),
# total duration = 1824ms (~1.8s).
#
# Design: brief settle then clean collapse to dormant dot.
#   Frames 0-1  (304ms): Hold at full (settling moment)
#   Frames 2-9  (1216ms): Gradual collapse — mirrors starting frames 7-2,
#               then settles to a visible dormant dot (larger than starting seed)
#   Frames 10-11 (304ms): Hold dormant dot
FRAMES = [
    (1.00, 1.00),  #  0: Full starburst
    (1.00, 1.00),  #  1: Hold (brief settle)
    (0.92, 0.90),  #  2: Begin collapse
    (0.83, 0.79),  #  3: Shrinking
    (0.72, 0.66),  #  4: Past halfway
    (0.60, 0.53),  #  5: Halfway
    (0.48, 0.40),  #  6: Smaller
    (0.36, 0.28),  #  7: Getting small
    (0.30, 0.24),  #  8: Nearly there
    (0.25, 0.20),  #  9: Dormant dot
    (0.25, 0.20),  # 10: Hold dormant dot
    (0.25, 0.20),  # 11: Hold dormant dot
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
    """Generate the 12-frame stopping sprite SVG.

    Uses <defs> + <use> with transform to avoid duplicating the path data 12 times.
    Each frame scales the base starburst around the center of its 100x100 slot.

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
