# qmllint on this project

How to run `qmllint` so it produces real diagnostics, why the obvious way does
not, and how to tighten the policy over time.

## TL;DR

```bash
./scripts/gen-qmllint-tree.py                        # once per branch, or after adding/renaming a .qml
/usr/lib/qt6/bin/qmllint -I build/qmllint <file>.qml
```

Never run bare `qmllint`, and never run it without `-I build/qmllint`. Both
mistakes fail quietly rather than loudly.

## Two traps, both silent

### 1. `/usr/bin/qmllint` is the wrong binary

Arch ships two tools named `qmllint`:

| Path | Package | Reports | Behaviour on this repo |
|---|---|---|---|
| `/usr/bin/qmllint` | `qt5-declarative` | `qmllint 1.0` | exit 255, **no output**, on ~93% of files |
| `/usr/lib/qt6/bin/qmllint` | `qt6-declarative` | `qmllint 6.11.1` | real diagnostics |

The Qt5 tool predates Quickshell's pragmas and every warning category this
project relies on. It wins the bare-name PATH lookup because Arch symlinks Qt5
host tools into `/usr/bin` while leaving Qt6's under `/usr/lib/qt6/bin/` — the
same layout that already forces `.githooks/pre-commit` to call `qsb` by
absolute path.

**This is not a hypothetical.** It is the root cause of the CI outage that ran
from 2026-04-08 to 2026-08-24. It also produced a false entry in this project's
own documentation: `CLAUDE.md` asserted for months that "qmllint exits 255 with
no output on any file importing Quickshell types", which described the Qt5 tool
and was never true of Qt6's.

Both the CI script and the pre-commit hook now assert the major version and
abort with a named error rather than degrade.

### 2. `qs.*` imports do not resolve without a generated module tree

Quickshell synthesises the `qs` module from the config directory tree at
runtime — `config/Config.qml` is importable as `qs.config`.`Config` with no
`qmldir` anywhere. `qmllint` cannot do that; it resolves a module only through
a real `qmldir` file.

Skipping this step does not make the check stricter, it makes it useless:

| | findings | files with output |
|---|---|---|
| without the tree | ~13,500 | 358 of 408 |
| with the tree | ~1,100 | 228 of 408 |

The difference is one cascade. `import qs.config` fails, so `Config` is an
unqualified identifier, so every property read through it is unresolved. Two
categories (`unqualified`, `import`) accounted for 11,387 of those findings,
and `RequiredProperty` alone went from 253 findings to zero.

**Why the `qmldir` files are generated into `build/` instead of committed next
to the sources:** a `qmldir` in a source directory changes how *Quickshell*
resolves that directory at runtime, and this repository is the user's live
desktop shell. `scripts/gen-qmllint-tree.py` therefore mirrors the tree into
`build/qmllint/qs/` with one symlink per `.qml` plus a generated `qmldir` per
directory. The mirror preserves the real layout, so relative imports (`import
".."`, `import "../components"`) resolve through it too.

`build/` is gitignored. Regenerate after adding, renaming, or deleting a `.qml`
file; the script rebuilds from scratch, so stale symlinks cannot survive.

## The policy in `.qmllint.ini`

Levels are a measurement, not taste. Categories are split three ways:

- **`error`** — produced zero findings across all 408 files when the baseline
  was frozen. Free today, fails on the first new one. This is the ratchet.
- **`info`** — has a real backlog, recorded with its count in the file. Prints
  on every run, does not affect the exit code.
- **`disable`** — measures something that cannot apply here, or produces
  false positives (see below).

### Promoting a category

1. Drive its count to zero.
2. Re-run the **full** sweep — categories interact, and a count taken from a
   partial run is wrong.
3. Move the line to the `error` block in the same commit as the last fix.

The CI job prints a per-category tally on every run, green ones included, so
the backlog is always visible without running anything locally.

### What the ratchet already buys

Two failure modes that `CLAUDE.md` previously listed as undetectable are now
caught, verified by reproducing each bug:

- **`readonly property` blocking an internal write** (`ReadOnlyProperty`, at
  `error`). Restoring the `QuietMode.enabled` regression makes qmllint report
  `Cannot assign to read-only property enabled` at both assignment sites and
  exit non-zero. This one fails the build today.
- **A singleton missing `import QtQuick` for `Component.onCompleted`**
  (`UnresolvedType` + `UnqualifiedAccess`). Deleting the import from
  `services/Theme.qml` — the exact change that stops the shell from starting —
  is reported at the correct line. It does **not** fail the build yet, because
  both categories still carry a backlog. Clearing `UnresolvedType` (72
  findings) would convert a shell-breaking class of bug into a hard CI failure,
  which makes it the highest-value promotion target on the list.

### Categories deliberately left disabled

`AttachedPropertyReuse`, `Quick.AttachedPropertyReuse`, and
`Quick.ControlsAttachedPropertyReuse` are off — Qt's own defaults. They fire on
any `Repeater`/`ListView` delegate, because the delegate and the view carry the
same attached type, and **the fix they suggest is wrong**. On
`SpecialWorkspaces.qml:123` they proposed rewriting the delegate's
`ListView.isCurrentItem` as `view.ListView.isCurrentItem`, which reads the
view's own attached object — a different value, and a live bug.

`Quick.LayoutsPositioning` is at `info` for a related reason: its single
finding, `modules/askpass/Content.qml:267`, is a false positive. The `Behavior
on y` there animates `transform: Translate { y: ... }`, and that `y` belongs to
the Translate, not to the layout-managed `RowLayout`.

The lesson generalises: **zero findings today is necessary but not sufficient
to promote a category.** Read the findings a category *does* produce before
trusting it, or the ratchet will eventually demand a wrong fix.

## CI

`.github/workflows/lint.yml` runs two independent jobs.

`shellcheck` runs on plain `ubuntu-latest` — the tool is preinstalled and the
job takes seconds, so it never waits on Nix.

`qmllint` runs under `nix develop`, not apt, because apt cannot supply what the
check needs. Ubuntu 24.04 ships Qt 6.4.2 against a project targeting 6.11, and
has neither Quickshell nor this project's own C++ plugin — without those,
`import Quickshell` and `import Symmetria` fail and the baseline is measuring a
different codebase. The flake's devShell carries both, pinned by `flake.lock`
to the same versions the shell runs against. `qt6.qtdeclarative` is listed
explicitly in the devShell's `packages` even though `inputsFrom` already pulls
it in transitively, because the lint job depends on `qmllint` being on PATH and
a transitive build input is not a contract.

The runner script is `.github/scripts/run-qmllint.sh`. Every guard in it traces
to one half of the original failure:

- It resolves the tool once and aborts with a single named error if it is
  missing. The old inline loop captured stderr into the variable it tested for
  diagnostics, so `qmllint: command not found` was reported as **408 identical
  code defects**.
- It asserts the major version is 6 or newer, which catches trap 1 above.
- It asserts the shadow tree exists, which catches trap 2.
- It branches on the **exit code**, never on whether output is non-empty.
  Findings at `info` print text and exit 0 by design, so an emptiness test
  would fail the build on all ~1,100 baseline findings.
- It prints the version, the policy path, and the import paths on every run,
  green included. The outage lasted four months because the one step that would
  have exposed it ran `qmllint --version || true` and went green on failure.
