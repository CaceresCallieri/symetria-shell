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

`.github/workflows/lint.yml` runs both checks in **one job**, under
`nix develop .#lint`, with `if: !cancelled()` on every check step.

Three decisions, each with a reason that cost a red run to learn:

**Under Nix, not apt.** Ubuntu 24.04 ships Qt 6.4.2 against a project targeting
6.11, and has neither Quickshell nor this project's C++ plugin — without those,
`import Quickshell` fails and the baseline measures a different codebase. The
runner's preinstalled shellcheck drifted too (see below). The flake pins both
tools through `flake.lock`, so CI and developers run the same versions.

**One job, not two.** The Nix store restore is the expensive part, and two jobs
contend over one cache key.

**Every step guarded with `if: !cancelled()`.** This is the fix for how the
outage hid for four months. `shellcheck` used to be the last step of a job
whose `qmllint` step exited 1 first, so it **never executed once** — and when
it finally ran it failed on three files that nobody knew about. One broken
check must never mask the ones after it.

### The `lint` devShell, and why it is separate

The lint job uses a dedicated `devShells.lint`, not the default one, and the
distinction is load-bearing.

The default devShell uses `inputsFrom = [shell shell.plugin shell.extras]`. The
main package lists `plugin` in its `buildInputs`, so entering it forces the
`symmetria-qml-plugin` derivation to build — and **that build has been failing
since before 2026-05** on `pkg_check_modules(Cava IMPORTED_TARGET libcava
REQUIRED)`. It is the same break that makes every `update-flake-inputs` run
red. `nix develop` on this project does not work today.

Removing the plugin from `QML_IMPORT_PATH` does not avoid it, because
`inputsFrom` drags the derivation in regardless. Hence a separate shell that
declares exactly what the checks need and nothing else.

**The cost, stated plainly:** CI cannot resolve `Symmetria`,
`Symmetria.Internal` or `Symmetria.Services`, because those modules come from
that same plugin. Three categories — `MissingType`, `RequiredProperty`,
`UnresolvedAlias` — measure zero on a developer machine but fire on 13 files in
CI with environmental findings (`Component is missing required property
modelData from AgentChipFor`). They sit in a `BLOCKED` block in `.qmllint.ini`
and go back to `error` the moment the plugin builds. **Fixing that derivation
is the single highest-value follow-up here**: it repairs a second permanently
red workflow and restores `RequiredProperty`, which guards the delegate
property-shadowing trap.

`QML_IMPORT_PATH` is set explicitly rather than left to Qt's setup hooks.
nixpkgs splits `qtdeclarative`'s binaries from its QML modules across store
outputs, so qmllint's default import directory — which it derives from the
location of its own binary — resolves nothing at all. The first CI run reported
6,268 import errors including `import QtQuick` before this was set.

### The runner scripts

`.github/scripts/run-qmllint.sh`. Every guard in it traces to one half of the
original failure:

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

`.github/scripts/run-shellcheck.sh` exists for the same reason, one layer down.
The runner shipped shellcheck 0.9.0 while developers ran 0.11.0, and the two
disagreed on this repository in both directions: `SC2317` was renamed `SC2329`,
so the repo's exclusion silently did not apply on the runner, and 0.9.0 raises
`SC2015` on `A && B || true` where 0.11.0 does not. Both identifiers are now
excluded, and the version is pinned and printed.

## qmlformat: local-only, and why

`.github/scripts/run-qmlformat.sh` runs in the **pre-commit hook only**. CI does
not run it. Two independent problems put it there.

**It fails silently on 10 of 408 files.** qmlformat exits 1 with zero bytes of
output and no diagnostic. The obvious gate — `qmlformat "$f" | diff -u "$f" -` —
reads that empty output as a full-file deletion and reports a crashed tool as a
formatting violation, which is the same defect that made the old workflow report
a missing binary as 408 code findings. The script branches on the exit code
instead and reports those files as tooling failures.

One minimal trigger is isolated: declaring a property named `id`.

```qml
import QtQuick
QtObject { readonly property string id: "x" }   // qmlformat: exit 1, no output
```

That is legal QML — qmllint accepts it and the shell runs it. It accounts for
`services/Notifs.qml` and `modules/controlcenter/PaneRegistry.qml`. The other
eight fail for reasons not yet isolated.

**Its output is version-coupled.** nixpkgs pins Qt 6.10.1 while Arch ships
6.11.1. On a tree formatted with 6.11.1, CI's 6.10.1 called **18 files
unformatted and reported a different set as unprocessable**. Neither is a
defect. Gating CI on that would mean permanent red, which is the exact failure
this whole setup exists to remove.

So the gate lives where exactly one Qt version is ever in play. Anything that
reformats QML must run on the machine that commits it. Restore the CI step if
both sides ever share a Qt version, and re-check after Qt 6.14 regardless —
QTBUG-144943 rewrites qmlformat from the DOM onto the AST, moving both the
output and the failure set.

## Pin the tool, not just the config

Four separate failures on this branch were one tool disagreeing with another
version of itself, and none of them was a finding about the code:

| Tool | Disagreement | Resolution |
|---|---|---|
| qmllint | Qt 5.15 vs Qt 6.11 | absolute path + a major-version assertion |
| shellcheck | 0.9.0 (runner) vs 0.11.0 | pinned through the flake |
| qmlformat | 6.10.1 (CI) vs 6.11.1 | gate moved to the hook |
| pyrefly | 0.49.0 (nixpkgs) vs 1.2.0 | pinned via `uvx pyrefly@1.2.0` |

Every check step therefore prints its tool version before running, on green runs
too. When a finding reproduces in CI but not locally, that line is the first
thing to read.

The deeper cause is that `flake.lock` is stale and internally inconsistent: it
still names `caelestia-cli` where `flake.nix` declares `symmetria-cli`, so nix
rewrites it on every run, and its nixpkgs pin has not moved since 2026-01-21
because every `update-flake-inputs` run fails on the unrelated libcava plugin
break. **Fixing that derivation would let the lock advance and would likely
retire both the pyrefly pin and the qmlformat exclusion.**

### Verifying the check is not hollow

A green run proves nothing on its own — the previous workflow was designed to
be a no-op and would have gone green too. The check was falsified before this
was merged: reintroducing the `QuietMode.enabled` `readonly` regression turned
CI red at both assignment sites, and reverting it turned CI green again. Repeat
that test after any change to `.qmllint.ini` that touches the `error` block.
