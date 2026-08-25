#!/usr/bin/env python3
"""Generate the eye-opening starting sprite sheet for ClaudeSparkle.

Reads the working sparkle sprite, extracts one frame (frame 0), and generates
a 9-frame sprite sheet using SVG <use> with scale transforms that create a
seed-to-full emergence animation.

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

# Emergence parameters
NUM_FRAMES = 9
START_SCALE = (0.15, 0.10)  # Tiny seed
END_SCALE = (1.0, 1.0)  # Full starburst


def ease_in_out_cubic(t: float) -> float:
    """Cubic ease-in-out: slow start, fast middle, slow end."""
    if t < 0.5:
        return 4 * t * t * t
    return 1 - (-2 * t + 2) ** 3 / 2


# Design: eased emergence from seed to full starburst.
# Cubic ease-in-out makes the seed linger, accelerate through mid-growth,
# then gently settle into full scale.
FRAMES = []
for _i in range(NUM_FRAMES):
    t = _i / (NUM_FRAMES - 1)
    e = ease_in_out_cubic(t)
    sx = START_SCALE[0] + (END_SCALE[0] - START_SCALE[0]) * e
    sy = START_SCALE[1] + (END_SCALE[1] - START_SCALE[1]) * e
    FRAMES.append((round(sx, 3), round(sy, 3)))


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
    """Generate the starting sprite SVG.

    Uses <defs> + <use> with transform to avoid duplicating the path data.
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
