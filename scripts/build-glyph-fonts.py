#!/usr/bin/env python3
"""Build the shell's Phosphor glyph fonts from assets/glyphs/glyph-map.json.

Every icon in the shell is a MaterialIcon whose `text` is a Material Symbols
name ("volume_up"). Material Symbols turns that name into a glyph with an
OpenType ligature. This script builds two fonts that do the same thing with
Phosphor's artwork: each name in glyph-map.json becomes a ligature that
resolves to the mapped Phosphor glyph. MaterialIcon then switches icon family
by switching `font.family` alone, so no caller, helper or config file has to
learn a second vocabulary (services/Theme.qml `glyphs`).

Inputs:
  - assets/glyphs/glyph-map.json: Material name -> Phosphor name. The only file
    to edit by hand. Keys must use [a-z0-9_]; `brand_*` keys are not Material
    names, they exist for tray substitutions.
  - @phosphor-icons/web at PHOSPHOR_VERSION, downloaded from the npm registry
    and checked against PHOSPHOR_INTEGRITY.

Outputs (commit them with the map):
  - assets/glyphs/SymmetriaPhosphor-Light.ttf and -Fill.ttf, subset to the
    mapped glyphs. Fill draws `fill: 1` icons; Phosphor uses one codepoint per
    icon across all its weights, so both fonts share one ligature table.
  - assets/glyphs/glyph-names.json: the names baked into the fonts and the
    SHA-256 of the map they came from. QML reads THIS file, never the map, so a
    map edit without a rebuild changes nothing instead of claiming glyphs the
    fonts lack. scripts/tests/test_glyph_fonts.py fails until the rebuild.

Run: python3 scripts/build-glyph-fonts.py   (needs fontTools: python-fonttools)
"""

from __future__ import annotations

import base64
import hashlib
import io
import json
import re
import tarfile
import urllib.request
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph

PHOSPHOR_VERSION = "2.1.2"
PHOSPHOR_URL = (
    f"https://registry.npmjs.org/@phosphor-icons/web/-/web-{PHOSPHOR_VERSION}.tgz"
)
PHOSPHOR_INTEGRITY = "sha512-rPAR9o/bEcp4Cw4DEeZHXf+nlGCMNGkNDRizYHM47NLxz9vvEHp/Tt6FMK1NcWadzw/pFDPnRBGi/ofRya958A=="

REPO_ROOT = Path(__file__).resolve().parent.parent
GLYPH_DIR = REPO_ROOT / "assets" / "glyphs"
MAP_PATH = GLYPH_DIR / "glyph-map.json"
NAMES_PATH = GLYPH_DIR / "glyph-names.json"

FAMILY = "Symmetria Phosphor"
# Weight -> member of the npm tarball.
SOURCE_FONTS = {
    "Light": "package/src/light/Phosphor-Light.ttf",
    "Fill": "package/src/fill/Phosphor-Fill.ttf",
}
CODEPOINT_CSS = "package/src/light/style.css"
LICENSE_MEMBER = "package/LICENSE"

# Characters a Material name can contain. Each becomes an empty, zero-width
# glyph so that a name the fonts do not cover renders as nothing rather than
# as letters; MaterialIcon falls back to Material Symbols for those anyway.
NAME_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789_"
NAME_PATTERN = re.compile(r"[a-z][a-z0-9_]*")

# Fixed so a rebuild from unchanged inputs produces identical bytes.
FONT_TIMESTAMP = 0


def fetch_package() -> dict[str, bytes]:
    with urllib.request.urlopen(PHOSPHOR_URL, timeout=60) as response:
        tarball = response.read()
    digest = "sha512-" + base64.b64encode(hashlib.sha512(tarball).digest()).decode()
    if digest != PHOSPHOR_INTEGRITY:
        raise SystemExit(f"integrity mismatch for {PHOSPHOR_URL}: {digest}")
    wanted = {*SOURCE_FONTS.values(), CODEPOINT_CSS, LICENSE_MEMBER}
    members: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(tarball), mode="r:gz") as archive:
        for member in archive.getmembers():
            if member.name in wanted:
                extracted = archive.extractfile(member)
                if extracted is not None:
                    members[member.name] = extracted.read()
    missing = wanted - members.keys()
    if missing:
        raise SystemExit(f"missing from the package: {sorted(missing)}")
    return members


def phosphor_codepoints(css: str) -> dict[str, int]:
    pattern = r'\.ph-light\.ph-([a-z0-9-]+):before\s*\{\s*content:\s*"\\([0-9a-f]+)"'
    return {m.group(1): int(m.group(2), 16) for m in re.finditer(pattern, css)}


def load_map(codepoints: dict[str, int]) -> dict[str, int]:
    """Material name -> Phosphor codepoint, validated."""
    mapping: dict[str, str] = json.loads(MAP_PATH.read_bytes())
    problems = [
        f"{name}: not [a-z][a-z0-9_]*"
        for name in mapping
        if not NAME_PATTERN.fullmatch(name)
    ]
    problems += [
        f"{name}: no Phosphor glyph '{ph}'"
        for name, ph in mapping.items()
        if ph not in codepoints
    ]
    if problems:
        raise SystemExit("glyph-map.json:\n  " + "\n  ".join(problems))
    return {name: codepoints[ph] for name, ph in mapping.items()}


def letter_glyph(character: str) -> str:
    return f"name.{ord(character):04x}"


def ligature_features(font: TTFont, ligatures: dict[str, int]) -> str:
    cmap = font.getBestCmap()
    # Longest first: OpenType applies the first ligature that matches, so
    # "timer_1" must be tried before "timer".
    rules = [
        f"    sub {' '.join(letter_glyph(c) for c in name)} by {cmap[codepoint]};"
        for name, codepoint in sorted(
            ligatures.items(), key=lambda item: (-len(item[0]), item[0])
        )
    ]
    body = "\n".join(rules)
    # `rlig` beside `liga`: required ligatures cannot be switched off by a
    # caller's font features, and these ligatures ARE the glyph lookup.
    return (
        "languagesystem DFLT dflt;\nlanguagesystem latn dflt;\n"
        f"lookup names {{\n{body}\n}} names;\n"
        "feature liga { lookup names; } liga;\n"
        "feature rlig { lookup names; } rlig;\n"
    )


def add_letter_glyphs(font: TTFont) -> None:
    # Assigning into `glyf` also appends the name to the font's glyph order.
    for character in NAME_ALPHABET:
        name = letter_glyph(character)
        font["glyf"][name] = Glyph()
        font["hmtx"][name] = (0, 0)
        for table in font["cmap"].tables:
            if table.isUnicode():
                table.cmap[ord(character)] = name


def rename(font: TTFont, weight: str) -> None:
    family = f"{FAMILY} {weight}"
    postscript = f"SymmetriaPhosphor-{weight}"
    names = font["name"]
    names.names = [
        record for record in names.names if record.nameID not in (1, 2, 3, 4, 6, 16, 17)
    ]
    for name_id, value in (
        (1, family),
        (2, "Regular"),
        (3, f"{postscript};{PHOSPHOR_VERSION}"),
        (4, family),
        (6, postscript),
    ):
        names.setName(value, name_id, 3, 1, 0x409)
        names.setName(value, name_id, 1, 0, 0)


def build_font(source: bytes, weight: str, ligatures: dict[str, int]) -> TTFont:
    font = TTFont(io.BytesIO(source), recalcTimestamp=False)
    # Phosphor ships its own ligatures, keyed by Phosphor names. They would
    # compete with the Material names, so the table is rebuilt from scratch.
    del font["GSUB"]
    add_letter_glyphs(font)
    addOpenTypeFeaturesFromString(font, ligature_features(font, ligatures))

    cmap = font.getBestCmap()
    keep = [cmap[codepoint] for codepoint in set(ligatures.values())]
    keep += [letter_glyph(c) for c in NAME_ALPHABET]
    options = Options()
    options.layout_features = ["liga", "rlig"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = Subsetter(options=options)
    subsetter.populate(
        glyphs=keep, unicodes=[*ligatures.values(), *map(ord, NAME_ALPHABET)]
    )
    subsetter.subset(font)

    rename(font, weight)
    font["head"].created = FONT_TIMESTAMP
    font["head"].modified = FONT_TIMESTAMP
    return font


def main() -> None:
    package = fetch_package()
    codepoints = phosphor_codepoints(package[CODEPOINT_CSS].decode())
    ligatures = load_map(codepoints)
    for weight, member in SOURCE_FONTS.items():
        font = build_font(package[member], weight, ligatures)
        out = GLYPH_DIR / f"SymmetriaPhosphor-{weight}.ttf"
        font.save(out, reorderTables=True)
        font.close()
        print(f"wrote {out.relative_to(REPO_ROOT)} ({out.stat().st_size} bytes)")
    (GLYPH_DIR / "Phosphor-LICENSE.txt").write_bytes(package[LICENSE_MEMBER])
    names = {
        "generatedBy": "scripts/build-glyph-fonts.py",
        "phosphorVersion": PHOSPHOR_VERSION,
        "mapSha256": hashlib.sha256(MAP_PATH.read_bytes()).hexdigest(),
        "names": sorted(ligatures),
    }
    NAMES_PATH.write_text(json.dumps(names, indent=2) + "\n")
    print(f"wrote {NAMES_PATH.relative_to(REPO_ROOT)} ({len(ligatures)} names)")


if __name__ == "__main__":
    main()
