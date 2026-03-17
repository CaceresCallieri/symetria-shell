#!/usr/bin/env python3
"""Preview all frames of a sprite sheet side-by-side.

Extracts individual frames from a vertical sprite strip and renders them
at multiple sizes for visual inspection of morph progression.

Usage:
    python scripts/test-sprite-preview.py assets/claude-sparkle-ask-morph-sprite.svg
    python scripts/test-sprite-preview.py assets/claude-sparkle-plan-morph-sprite.svg

Output:
    /tmp/sprite-preview.png — screenshot showing all frames at 64px and 15px
"""

import sys
import os
import re
import subprocess
import xml.etree.ElementTree as ET

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_sprite(svg_path):
    """Extract individual frames from a vertical sprite sheet."""
    full_path = os.path.join(BASE_DIR, svg_path) if not os.path.isabs(svg_path) else svg_path
    tree = ET.parse(full_path)
    root = tree.getroot()
    ns = {"svg": "http://www.w3.org/2000/svg"}

    # Parse viewBox to get frame dimensions
    vb = root.get("viewBox", "0 0 100 100").split()
    vb_w, vb_h = float(vb[2]), float(vb[3])
    frame_h = vb_w  # Each frame is square: 100x100
    num_frames = int(vb_h / frame_h)

    frames = []
    paths = root.findall(".//svg:path", ns) or root.findall(".//path")
    for i, path_el in enumerate(paths):
        d = path_el.get("d", "")
        fill = path_el.get("fill", "black")
        fill_rule = path_el.get("fill-rule", "")
        comment = ""
        # Try to get preceding comment
        prev = path_el.getprevious() if hasattr(path_el, "getprevious") else None

        frame_svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {int(frame_h)} {int(frame_h)}">'
        fr = f' fill-rule="{fill_rule}"' if fill_rule else ""
        frame_svg += f'<path fill="#d97757"{fr} d="{d}"/>'
        frame_svg += "</svg>"
        frames.append(frame_svg)

    return frames, num_frames, os.path.basename(svg_path)


def build_html(frames, num_frames, filename):
    """Build HTML preview page showing all frames."""
    sizes = [64, 15]

    rows_html = ""
    for size in sizes:
        cells = []
        for i, frame_svg in enumerate(frames):
            # Inject width/height
            sized = frame_svg.replace("<svg ", f'<svg width="{size}" height="{size}" ')
            pad = max(size + 8, 23)
            cells.append(
                f'<div class="frame">'
                f'<div class="icon-box" style="width:{pad}px;height:{pad}px;">{sized}</div>'
                f'<span class="frame-num">{i}</span>'
                f"</div>"
            )
        cells_html = "\n        ".join(cells)
        rows_html += f"""
    <div class="size-row">
        <span class="size-label">{size}px</span>
        <div class="frames-row">
            {cells_html}
        </div>
    </div>"""

    return f"""<!DOCTYPE html>
<html><head>
<style>
body {{
    background: #1a1a2e;
    padding: 20px;
    font-family: system-ui, sans-serif;
    color: #ccc;
    margin: 0;
}}
h2 {{ color: #d97757; margin: 0 0 5px; font-size: 16px; }}
.subtitle {{ color: #666; font-size: 12px; margin-bottom: 16px; }}
.size-row {{
    display: flex;
    align-items: flex-start;
    gap: 12px;
    margin: 8px 0;
}}
.size-label {{
    width: 40px;
    text-align: right;
    font-size: 12px;
    color: #555;
    padding-top: 8px;
    flex-shrink: 0;
}}
.frames-row {{
    display: flex;
    gap: 4px;
    flex-wrap: wrap;
}}
.frame {{
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
}}
.frame-num {{
    font-size: 9px;
    color: #444;
}}
.icon-box {{
    background: #2a2a3e;
    border-radius: 4px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 1px solid #333;
}}
</style>
</head><body>
<h2>Sprite Frame Preview</h2>
<p class="subtitle">{filename} — {num_frames} frames</p>
{rows_html}
</body></html>"""


def main():
    svg_file = sys.argv[1] if len(sys.argv) > 1 else "assets/claude-sparkle-ask-morph-sprite.svg"

    frames, num_frames, filename = parse_sprite(svg_file)

    html = build_html(frames, num_frames, filename)

    html_path = "/tmp/sprite-preview.html"
    png_path = "/tmp/sprite-preview.png"

    with open(html_path, "w") as f:
        f.write(html)

    result = subprocess.run(
        ["npx", "playwright", "screenshot", "--full-page", "-b", "chromium",
         f"file://{html_path}", png_path],
        capture_output=True, text=True,
    )

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(png_path)


if __name__ == "__main__":
    main()
