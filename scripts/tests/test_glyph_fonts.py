"""The glyph fonts must be rebuilt whenever their map changes.

QML reads assets/glyphs/glyph-names.json, which scripts/build-glyph-fonts.py
writes together with the fonts. A map edit without a rebuild leaves the fonts
behind the map, and the edit silently changes nothing on screen.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

GLYPH_DIR = Path(__file__).resolve().parents[2] / "assets" / "glyphs"
REBUILD = (
    "glyph-map.json changed without a rebuild: run python3 scripts/build-glyph-fonts.py"
)


def built() -> dict[str, object]:
    return json.loads((GLYPH_DIR / "glyph-names.json").read_text())


def test_fonts_were_built_from_the_current_map() -> None:
    current = hashlib.sha256((GLYPH_DIR / "glyph-map.json").read_bytes()).hexdigest()
    assert built()["mapSha256"] == current, REBUILD


def test_built_names_are_the_map_keys() -> None:
    mapped = sorted(json.loads((GLYPH_DIR / "glyph-map.json").read_text()))
    assert built()["names"] == mapped, REBUILD


def test_both_fonts_exist() -> None:
    for weight in ("Light", "Fill"):
        assert (GLYPH_DIR / f"SymmetriaPhosphor-{weight}.ttf").stat().st_size > 0
