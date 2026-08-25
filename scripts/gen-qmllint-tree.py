#!/usr/bin/env python3
"""Generate a shadow QML module tree so qmllint can resolve `qs.*` imports.

Quickshell synthesises the `qs` module from the config directory tree at
runtime: `config/Config.qml` is importable as `qs.config`.`Config`, with no
`qmldir` file anywhere. `qmllint` cannot do that — it resolves a module only
through a real `qmldir`. Without one, every `import qs.config` fails, `Config`
becomes an unqualified identifier, and the resulting noise (11k+ warnings)
buries every real diagnostic.

Writing `qmldir` files into the source directories would fix qmllint and break
Quickshell: a `qmldir` changes how Quickshell itself resolves the directory at
runtime, and this repo IS the user's live shell. So this script builds the
tree somewhere else instead:

    build/qmllint/qs/<mirror of the repo>/
        <symlink per .qml file>
        qmldir            <- generated, declares `module qs.<dotted.path>`

Point qmllint at the parent (`-I build/qmllint`) and `qs.config` resolves.
The symlinks mirror the real directory layout, so relative imports (`import
".."`, `import "../components"`) resolve through the shadow tree too.

Usage:
    scripts/gen-qmllint-tree.py [--out build/qmllint]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Directories that hold no shell QML, or hold generated copies of it. `build`
# contains the compiled plugin's own qmldir files — mirroring those would
# declare the `Symmetria` C++ module twice under two different names.
SKIP_DIRS = {".git", "build", "node_modules", "__pycache__", ".direnv", ".cache", "result"}

# A `qmldir` entry needs a version. Quickshell's synthesised modules are
# unversioned, so the number is arbitrary — it only has to parse and to match
# what the import statements ask for (they ask for nothing, so any version is
# accepted as the sole candidate).
MODULE_VERSION = "1.0"


def is_singleton(qml_file: Path) -> bool:
    """Detect `pragma Singleton`, which a qmldir entry must repeat.

    A singleton declared in QML but not in its qmldir is a hard error in
    qmllint, not a warning — it reports the type as uncreatable.
    """
    try:
        with qml_file.open(encoding="utf-8", errors="replace") as handle:
            for line in handle:
                stripped = line.strip()
                if stripped.startswith("pragma Singleton"):
                    return True
                # Pragmas must precede every import and the root object, so
                # the first import ends the region worth scanning.
                if stripped.startswith("import "):
                    return False
    except OSError:
        return False
    return False


def qml_directories(repo_root: Path) -> list[Path]:
    """Every directory holding at least one .qml file, skipping SKIP_DIRS."""
    found: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(repo_root):
        dirnames[:] = sorted(name for name in dirnames if name not in SKIP_DIRS)
        if any(name.endswith(".qml") for name in filenames):
            found.append(Path(dirpath))
    return found


def module_name(repo_root: Path, directory: Path) -> str:
    """`services/` -> `qs.services`; the repo root -> `qs`."""
    relative = directory.relative_to(repo_root)
    if relative == Path("."):
        return "qs"
    return "qs." + ".".join(relative.parts)


def write_shadow_directory(repo_root: Path, directory: Path, out_root: Path) -> int:
    """Mirror one directory into the shadow tree. Returns the file count."""
    relative = directory.relative_to(repo_root)
    shadow = out_root / "qs" / relative
    shadow.mkdir(parents=True, exist_ok=True)

    entries: list[str] = []
    count = 0
    for qml_file in sorted(directory.glob("*.qml")):
        link = shadow / qml_file.name
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(qml_file.resolve())
        count += 1

        # A QML type name must start with an upper-case letter. `shell.qml` is
        # an entry point, not a type, so it gets a symlink (it still has to be
        # lintable) but no qmldir entry.
        type_name = qml_file.stem
        if not type_name[:1].isupper():
            continue

        prefix = "singleton " if is_singleton(qml_file) else ""
        entries.append(f"{prefix}{type_name} {MODULE_VERSION} {qml_file.name}")

    qmldir = [f"module {module_name(repo_root, directory)}", *entries, ""]
    (shadow / "qmldir").write_text("\n".join(qmldir), encoding="utf-8")
    return count


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default=str(repo_root / "build" / "qmllint"),
        help="Directory to write the shadow tree into (default: build/qmllint)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Print nothing on success",
    )
    args = parser.parse_args()

    out_root = Path(args.out).resolve()
    if out_root == repo_root or repo_root in out_root.parents and out_root.name == "qs":
        print(f"error: refusing to write the shadow tree to {out_root}", file=sys.stderr)
        return 1

    # Rebuild from scratch: a renamed or deleted .qml would otherwise leave a
    # dangling symlink behind and a stale qmldir entry pointing at it.
    shadow_root = out_root / "qs"
    if shadow_root.exists():
        for dirpath, dirnames, filenames in os.walk(shadow_root, topdown=False):
            for name in filenames:
                (Path(dirpath) / name).unlink()
            for name in dirnames:
                (Path(dirpath) / name).rmdir()
        shadow_root.rmdir()

    directories = qml_directories(repo_root)
    total = sum(write_shadow_directory(repo_root, d, out_root) for d in directories)

    if not args.quiet:
        print(f"qmllint tree: {total} file(s) in {len(directories)} module(s) -> {out_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
