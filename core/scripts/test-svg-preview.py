#!/usr/bin/env python3
"""Preview SVG icons at multiple sizes with orange colorization.

Renders the target SVG at 15px (actual agentbar size), 32px, 64px, and 128px,
alongside reference icons (key, plan) and a font '?' for comparison.

Usage:
    python scripts/test-svg-preview.py [svg_file]
    python scripts/test-svg-preview.py assets/ask-question-icon.svg

Output:
    /tmp/svg-icon-test.png  — screenshot of the preview page
"""

import sys
import os
import re
import subprocess

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

REFERENCE_ICONS = {
    "Key (ref)": "assets/key-permission-icon.svg",
    "Plan (ref)": "assets/plan-list-icon.svg",
}

SIZES = [15, 32, 64, 128]


def read_svg(path):
    full = os.path.join(BASE_DIR, path) if not os.path.isabs(path) else path
    with open(full) as f:
        return f.read()


def make_orange(svg_content):
    """Replace fill='black' with orange for preview."""
    return svg_content.replace('fill="black"', 'fill="#d97757"')


def svg_at_size(svg_content, size):
    """Inject width/height attributes into the <svg> element."""
    return re.sub(
        r"<svg\s",
        f'<svg width="{size}" height="{size}" ',
        svg_content,
        count=1,
    )


def build_html(svg_file, test_svg, ref_svgs):
    """Build the full HTML preview page."""
    columns = [("Test Icon", test_svg)] + [
        (name, svg) for name, svg in ref_svgs.items()
    ]

    # Header row
    header_cells = "".join(
        f'<span class="header-label">{name}</span>' for name, _ in columns
    )
    header_cells += '<span class="header-label">Font ?</span>'

    # Size rows
    rows = []
    for size in SIZES:
        cells = []
        for _, svg in columns:
            sized = svg_at_size(svg, size)
            pad = max(size + 10, 25)
            cells.append(
                f'<div class="icon-box" style="width:{pad}px;height:{pad}px;">'
                f"{sized}</div>"
            )
        # Font reference ?
        cells.append(
            f'<span style="color:#d97757;font-size:{size}px;font-weight:bold;'
            f'line-height:1;display:inline-flex;align-items:center;'
            f'justify-content:center;width:{max(size+10,25)}px;'
            f'height:{max(size+10,25)}px;">?</span>'
        )
        row_html = "\n            ".join(cells)
        rows.append(
            f"""
        <div class="row">
            <span class="size-label">{size}px</span>
            {row_html}
        </div>"""
        )

    return f"""<!DOCTYPE html>
<html><head>
<style>
body {{
    background: #1a1a2e;
    padding: 30px;
    font-family: system-ui, sans-serif;
    color: #ccc;
    margin: 0;
}}
h2 {{
    color: #d97757;
    margin: 0 0 5px;
    font-size: 16px;
}}
.subtitle {{
    color: #666;
    font-size: 12px;
    margin-bottom: 20px;
}}
.header-row {{
    display: flex;
    align-items: center;
    gap: 16px;
    margin-bottom: 8px;
    padding-left: 86px;
}}
.header-label {{
    color: #888;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 1px;
    min-width: 60px;
    text-align: center;
}}
.row {{
    display: flex;
    align-items: center;
    gap: 16px;
    margin: 10px 0;
}}
.size-label {{
    width: 70px;
    text-align: right;
    font-size: 13px;
    color: #555;
    font-variant-numeric: tabular-nums;
}}
.icon-box {{
    background: #2a2a3e;
    border-radius: 6px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 1px solid #333;
}}
</style>
</head><body>
<h2>SVG Icon Preview</h2>
<p class="subtitle">Testing: {os.path.basename(svg_file)}</p>
<div class="header-row">
    {header_cells}
</div>
{"".join(rows)}
</body></html>"""


def main():
    svg_file = sys.argv[1] if len(sys.argv) > 1 else "assets/ask-question-icon.svg"

    test_svg = make_orange(read_svg(svg_file))
    ref_svgs = {name: make_orange(read_svg(path)) for name, path in REFERENCE_ICONS.items()}

    html = build_html(svg_file, test_svg, ref_svgs)

    html_path = "/tmp/svg-icon-test.html"
    png_path = "/tmp/svg-icon-test.png"

    with open(html_path, "w") as f:
        f.write(html)

    result = subprocess.run(
        [
            "npx", "playwright", "screenshot",
            "--full-page",
            "-b", "chromium",
            f"file://{html_path}",
            png_path,
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(png_path)


if __name__ == "__main__":
    main()
