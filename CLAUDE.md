# CLAUDE.md

> **Principle: No duplicate sources of truth.** This document contains ONLY information that cannot be discovered by reading the codebase. For implementation details, read the actual source files — they are the single source of truth.

## Project Overview

Symmetria Shell is a Quickshell-based desktop shell for Hyprland — a fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell) for personal customization.

**Do NOT use Chrome DevTools MCP tools** — this is a native Wayland desktop shell, not a web application. Use `grim` for screenshots.

**Do NOT start, restart, or kill the shell process.** The user runs Symmetria as their active desktop shell. **NEVER run `qs -c symmetria`, `symmetria shell -d`, `qs kill`, `pkill qs`, or any other launch/kill command** — not even for diagnostics. After QML/asset changes, clear the cache and inform the user that a restart is needed:
```bash
rm -rf ~/.cache/quickshell/qmlcache
# Let the user restart manually
```

This prohibits **launching and killing**. It does NOT prohibit **IPC against the already-running shell** — `symmetria shell <target> <function>` (e.g. `symmetria shell lock lock`) is normal usage and is how you exercise a running feature. The two are different commands that happen to share a prefix.

**Process management:** The QuickShell binary is `qs`, NOT `quickshell`. To check: `pgrep -fa qs | grep -v grep | grep -v zsh | grep -v python | grep -v claude`. `pkill quickshell` / `pgrep quickshell` match NOTHING — the process name is `qs`, which is the only reason the `pkill qs` form is mentioned here at all; killing is prohibited (see above).

## Build & Run

**QML / SVG / image changes** — no compilation needed. Clear the cache, then ask the user to restart (see the never-launch rule above):
```bash
rm -rf ~/.cache/quickshell/qmlcache
```

**Shader changes** (`assets/shaders/*.frag`) — compilation IS needed. The shell loads the compiled `.qsb`, never the `.frag`, so editing the `.frag` alone changes nothing and reports no error:
```bash
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
  -o assets/shaders/NAME.frag.qsb assets/shaders/NAME.frag
```

**C++ plugin changes** (`plugin/src/`):
```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR=$HOME/.config/quickshell/symmetria
cmake --build build
sudo cmake --install build
sudo chown -R $USER:$USER ~/.config/quickshell/symmetria
rm -rf ~/.cache/quickshell/qmlcache
```

**External plugin dependency: `Symmetria.FileManager.Models`** — The file dialog, wallpaper grid, and appearance pane import `Symmetria.FileManager.Models` (FileSystemModel) from the Symmetria File Manager project. This plugin must be built and installed separately:
```bash
cd ~/projects/symmetria-file-manager && ./build-plugin.sh
```
If missing, Symmetria will fail to load components that browse the filesystem. See symmetria-file-manager's CLAUDE.md for build details.

**CLI (`symmetria-cli`)** — Python CLI at `~/.config/quickshell/symmetria-cli/` providing screenshot, recording, scheme, wallpaper, and shell IPC commands. Installed manually (not via pacman):
- Source: `~/.config/quickshell/symmetria-cli/src/symmetria/`
- Installed to: `/usr/lib/python3.14/site-packages/symmetria/`
- Entry point: `/usr/bin/symmetria` (Python 3.14 shim)
- After editing CLI source, re-deploy:
```bash
sudo cp -rT ~/.config/quickshell/symmetria-cli/src/symmetria /usr/lib/python3.14/site-packages/symmetria
```
  The `-T` is required, NOT optional: the destination `symmetria/` already
  exists, so plain `cp -r src dest` copies *into* it (creating a nested, dead
  `symmetria/symmetria/`) and silently leaves the real top-level package — the
  one Python imports — untouched. `-T` treats the destination as the target so
  the package contents are overwritten in place.

## Pre-commit Hooks

Pre-commit hooks run `qmllint` and `qmlformat` on `.qml` files, `ruff` plus `pyrefly` on `.py` files, `shellcheck` on `.sh` files, and a shader-freshness check on `.frag` files. Setup (once per clone):
```bash
git config core.hooksPath .githooks
```
Requires: `qt6-declarative`, `shellcheck`, `ruff` (`paru -S shellcheck ruff`), plus `pyrefly` and `vulture` (`uv tool install pyrefly vulture`). Each check skips itself with a message when its tool is absent — a missing tool is never a finding.

**Never invoke `qmllint` by bare name.** `/usr/bin/qmllint` is Qt **5.15**'s tool
(package `qt5-declarative`); it exits 255 with no output on ~93% of this repo and
supports none of the warning categories the project relies on. The Qt6 tool is
`/usr/lib/qt6/bin/qmllint`, same as `qsb`. A bare invocation also skips `-I
build/qmllint`, without which `qs.*` imports do not resolve and the findings
inflate roughly twelvefold. The hook and CI both assert against these; a manual
run does not. → `docs/qmllint-setup.md`

## Deterministic Checks

Run these change-scoped checks during `/seal`, `/code-review`, and ad-hoc review. Substitute `<base>` with the commit the review target diffs against: the parent of one reviewed commit, or `<oldest>^` for a commit range.

```bash
./scripts/gen-qmllint-tree.py --quiet && git diff -z --name-only --diff-filter=ACMR <base> -- '*.qml' | xargs -0 -r /usr/lib/qt6/bin/qmllint -I build/qmllint  # QML types; regenerates the gitignored build/qmllint mirror first
git diff -z --name-only --diff-filter=ACMR <base> -- '*.qml' | xargs -0 -r .github/scripts/run-qmlformat.sh  # QML formatting
git diff -z --name-only --diff-filter=ACMR <base> -- '*.py' | xargs -0 -r ruff check --output-format concise
git diff -z --name-only --diff-filter=ACMR <base> -- '*.py' | xargs -0 -r ruff format --check
pyrefly check --baseline pyrefly-baseline.json  # types — whole project, new errors only
git diff -z --name-only --diff-filter=ACMR <base> -- '*.sh' | xargs -0 -r shellcheck -e SC2317,SC2329
```

**Exit-code and output semantics.** `qmllint` exits 0 on warnings by design since Qt 6.9, so its verdict comes from the categories `.qmllint.ini` promotes to `error`; a syntax error exits 255. `run-qmlformat.sh` exits 1 when a file differs from its formatted form, and reports a file qmlformat cannot process as a *tooling failure* rather than a finding — 10 files currently land there. `ruff check` and `ruff format --check` exit 1 on findings and 2 on a tool error; a 2 is a tooling failure, not a code finding. `pyrefly check` exits non-zero only for errors that survive the committed baseline. A blocking finding prevents completion until it is fixed or suppressed narrowly with a reason. A command that cannot execute is a tooling failure: report it and continue the review.

**Three ways to silently break these lines.**
1. Never rewrite `/usr/lib/qt6/bin/qmllint` as a bare `qmllint`. On Arch that resolves to Qt 5.15's tool, which exits 255 with no output on ~93% of this repo. The same trap applies to `qmlformat`.
2. Never drop `xargs -r`. `run-qmlformat.sh` sweeps *every* tracked file when called with no arguments, so without `-r` a docs-only change turns the change gate into a full-repo sweep that still reads as change-scoped.
3. Never scope `pyrefly` to changed files. A changed signature breaks callers the diff never touched; the committed baseline is what narrows it to new errors.

Suppressions live in `.qmllint.ini` (QML categories, each with its reason), `pyproject.toml` (`per-file-ignores`), and inline `# type: ignore[rule]` comments. Keep an inline suppression's marker short and put its explanation on the line *above* — `ruff format` rewraps long lines and will silently carry a trailing marker onto a different line, voiding it.

**Advisory backlog, not a gate.** `.qmllint.ini` parks 11 categories at `info` with their finding counts recorded. They print on every run and never affect the exit code. Three more sit in a `BLOCKED` block: they measure zero locally and are demoted only because CI cannot resolve the `Symmetria.*` modules. Treat all of these as `/tech-debt` evidence. → `docs/qmllint-setup.md`

## Full-Project Checks

Run every command during `/tech-debt`, a full codebase audit, and CI. Run all lines even when one reports findings.

```bash
./scripts/gen-qmllint-tree.py --quiet && .github/scripts/run-qmllint.sh
.github/scripts/run-qmlformat.sh
ruff check . --output-format concise
ruff format --check .
pyrefly check
vulture scripts/ --min-confidence 80
.github/scripts/run-shellcheck.sh
```

The repository gate starts clean for blocking findings: every one must be fixed, or suppressed narrowly with a reason, before setup is complete. The `pyrefly` line here deliberately omits the review baseline so an audit sees the true total. `vulture` is scoped to `scripts/` because that directory holds every tracked `.py` file. Note that `vulture` exits 0 on a file it cannot parse, so treat a suspiciously empty result as unverified rather than clean.

**`run-qmlformat.sh` is local-only — CI does not run it.** qmlformat's output is version-coupled, and the two sides disagree: nixpkgs pins Qt 6.10.1 while Arch ships 6.11.1. On a tree formatted with 6.11.1, 6.10.1 reported 18 files as unformatted and a *different* set as unprocessable. Neither is a defect. The gate therefore lives in the pre-commit hook, where exactly one Qt version is ever in play. Anything that reformats QML must run on the same machine that commits it.

**Not adopted, with reasons.** `pytest` — there is no Python test suite to run. `deptry` — it audits a dependency manifest, and `pyproject.toml` here carries tooling config only, with no `[project]` table by design. `jscpd` — duplication analysis across 11 standalone helper scripts is low value for a separate binary. QuickShell configs also have no viable test runner at all: `qmltestrunner` cannot load Quickshell's statically-linked plugins. → `docs/qmllint-setup.md`

## Branch Structure

| Branch | Purpose | Tracks |
|--------|---------|--------|
| `main` | Active development with customizations | `origin/main` |
| `base` | Original upstream shell code (reference) | `upstream/main` |
| `feature/*` | Feature branches for significant changes | — |

```bash
git diff base..main          # See all customizations vs original
git log base..main --oneline # Commits that diverge from upstream
git fetch upstream           # Update base (tracks upstream/main)
```

## Architecture

**Entry point:** `shell.qml` — loads `BackgroundModule.Wrapper`, `DrawersModule.Wrapper`, `AreaPickerModule.Wrapper`, Askpass, Stt, Lock, Shortcuts, BatteryMonitor, IdleMonitors.

| Directory | Purpose |
|-----------|---------|
| `modules/` | Main UI modules (bar, launcher, dashboard, lock, etc.) |
| `components/` | Reusable QML components (controls, effects, containers) |
| `services/` | Singleton services (Audio, Brightness, Network, Colours, etc.) |
| `config/` | Configuration system — reads `~/.config/symmetria/shell.json` |
| `plugin/` | C++ native plugins (Symmetria, Symmetria.Internal, Symmetria.Services) — note: Models moved to Symmetria File Manager |
| `utils/` | Utility functions and scripts |
| `assets/` | Static assets (images, shaders, PAM configs) |

**Key patterns:**
- **Singletons** — Services and Config are singletons: `import "services"` / `import "config"`
- **Configuration** — All settings flow through `config/Config.qml` → `~/.config/symmetria/shell.json`
- **Module entry points** — Each major module exposes `Wrapper.qml` as its entry point, imported via qualified alias: `import "modules/x" as XModule` → `XModule.Wrapper {}`. This avoids the last-import-wins collision pitfall. Modules without collision risk (e.g., `Stt`, `Keycaster`) keep their own name.
- **Drawer system** — `modules/drawers/` manages slide-out panels with unified visibility and gestures
- **Colours** — `services/Colours.qml` provides M3 color palette with light/dark + transparency support
- **Theme** — `services/Theme.qml` selects the surface design language along TWO orthogonal axes:
  `material` (clay | metal — how one surface looks, consumed by the surface primitives) and
  `form` (islands | panel — how surfaces are arranged, consumed by the bar geometry). Recipes are
  plain data tables, so a new material is a data block rather than a parallel implementation of
  every primitive. Switching is live (`symmetria shell surface material|form <name>`), but is
  **runtime-only — not persisted**; the shipped default lives in the property initialisers.
- **IPC** — `symmetria shell <target> <function>` (targets: drawers, notifs, lock, mpris, picker, wallpaper, askpass, stt, chords, agentbar, surface)


## Remote Agents (SSH Tunnel)

Symmetria can display agents from remote machines that tunnel their orchestrator socket over SSH. Detection is automatic: the bridge (`scripts/agent-bridge.py`) checks whether each connecting client's `nvim_pid` exists in local `/proc`. If it doesn't, the agent is marked `remote: true` and routed to a separate cloud-icon slot in the merged bar (or shown with a cloud badge in the non-merged bar).

**Setup on the remote machine:**

1. Forward the bridge socket over SSH:
   ```bash
   ssh -R /run/user/$UID/symmetria-agents-remote.sock:/run/user/$UID/symmetria-agents.sock user@host
   ```
   Or add to `~/.ssh/config` as `RemoteForward`.

2. Set `SYMMETRIA_AGENT_SOCKET` in the remote shell environment so hook scripts find the forwarded socket:
   ```bash
   export SYMMETRIA_AGENT_SOCKET=/run/user/$UID/symmetria-agents-remote.sock
   ```

**Known limitation:** If a remote client's `nvim_pid` coincidentally matches a running local process, the bridge will treat it as a local agent (false-negative). This is negligible in practice given the large Linux PID space, but means the remote cloud badge won't appear for that agent.

## Configuration

| Layer | Location | Purpose |
|-------|----------|---------|
| QML defaults | `config/*.qml` | Structure, schemas, defaults (version-controlled) |
| JSON overrides | `~/.config/symmetria/shell.json` | User preferences — **symlinked to the tracked `config/shell.json`** |

**The override file IS version-controlled.** `~/.config/symmetria/shell.json` is a
symlink to `config/shell.json` in this repo, so every settings change made in the
UI — and every live edit for debugging — dirties the working tree. Two consequences:
edits you make to "just the user config" WILL show up in `git status`, and
`config/shell.json` diffs routinely contain unrelated serializer churn (the shell's
JSON writer re-encodes unicode escapes on save). Review that file selectively before
staging rather than assuming its whole diff belongs to your change.

**JSON overrides always win.** If you edit a QML default but the value exists in shell.json, your change won't take effect. Check shell.json first when debugging config issues.

**Key paths:**
- User config: `~/.config/symmetria/shell.json`
- Profile picture: `~/.face`
- Wallpapers: `~/Pictures/Wallpapers/` (configurable via `paths.wallpaperDir`)
- Hyprland user config: `~/.config/symmetria/hypr-user.conf`

**Color scheme:** QML reads from `~/.local/state/symmetria/scheme.json` (the same file the CLI writes to). On first launch, `Colours.qml` copies the bundled default from `config/color-scheme.json` to the state path. The version-controlled file serves only as the initial seed template.

**Editing the seed does NOT change a running install.** `_initScheme` copies `config/color-scheme.json` only when the state file is *absent*, so a palette commit is invisible on every machine that has already launched the shell once. To apply one, write the state file too:
```bash
cp config/color-scheme.json ~/.local/state/symmetria/scheme.json
```
`Colours.qml`'s `FileView` has `watchChanges: true`, so this takes effect live — no restart. Two caveats: the state file also carries `name`/`flavour`/`mode`/`variant` keys the repo seed lacks (harmless — `load()` reads only `.colours` — but a blind copy drops them), and editing in place preserves the inode, which matters because an atomic replace can drop the watch.

**Palette saturation is load-bearing.** `metalPill()` splits "neutral surface" from "state colour" purely on `hslSaturation > metalConstants.accentSaturationThreshold` (0.05), so desaturating an accent role past that line silently strips its hue *and* its `accentLift`. JSON holds no comments; `Colours._warnOnUnderSaturatedAccents()` enforces the accent side at runtime. The container side has a hard floor — see the comment on `accentSaturationThreshold` for why the darkest containers must be achromatic.

## Critical Pitfalls

These are hard-won lessons from past bugs. Each is a brief summary — full explanations with code examples are in the linked docs.

**QML required property shadowing** — `required property string foo` creates a NEW shadow property; `required foo` uses the EXISTING one. Shadowing silently breaks delegate bindings. → `docs/qml-pitfalls.md`

**QML type naming collisions** — When multiple directory imports export the same type name, the last import wins. This silently replaces entire modules. Run `./scripts/check-qml-conflicts.sh` before adding new modules. → `docs/qml-pitfalls.md`

**Transparency compensation** — Components outside the unified `Backgrounds` system appear darker (50% vs 22.5% black). Must manually compute `generalBackgroundAlpha × transparency.base`. → `docs/qml-pitfalls.md`

**XOR mask inversion** — The drawers window input region uses XOR. Expanding `mainRect` SHRINKS the clickable area. The bar must stay OUTSIDE `mainRect` to receive input. Corollary: every `Panels` child is turned into a `Subtract` Region, so a child whose width OR height reaches 0 carves nothing and the pointer is never delivered there — with no error. Invisible hover zones must floor both dimensions while they are live. → `docs/qml-pitfalls.md`

**Cursor shadowing** — A `visible: true` MouseArea at highest z-order shadows ALL `cursorShape` settings below it, even when `enabled: false`. Overlay MouseAreas need both `enabled` and `visible` guards. → `docs/qml-pitfalls.md`

**Layout sizes in onCompleted** — `Component.onCompleted`, `Qt.callLater()`, and `Timer { interval: 0 }` all fire BEFORE ColumnLayout computes `implicitHeight` (polish phase). Use `onImplicitHeightChanged` for reliable post-polish values. Also: set model item state BEFORE adding to arrays (Repeater creates delegates synchronously). → `docs/qml-pitfalls.md`

**STT target locking** — Window and agent targets are captured once at `start()` and never re-resolved. Re-resolving at stop-time or delivery-time causes wrong-agent delivery because `activeAgentForTerminal()` is identity-unstable. → `docs/stt-design-decisions.md`

**List mutation in loops is O(n²)** — Never `push()` to a QML list property in a loop when computed properties (`.filter()`, `.map()`) bind to it. Each push triggers all bindings. Build a local array, assign once: `root.list = temp`. This caused a 23s startup freeze with 6,890 notifications. → `docs/qml-pitfalls.md`

**Qt HTTP/2 protocol errors** — Qt 6's `QNetworkAccessManager` enables HTTP/2 by default. Some servers (notably `ipinfo.io`) cause silent protocol errors that break the entire weather init chain. Disable per-request with `Http2AllowedAttribute = false`. → `docs/qt-http2-pitfall.md`

**STT `gpt-4o-transcribe` silently truncates long audio** — The model emits the transcript as output tokens and caps around ~2000 tokens (~10 min of speech), returning HTTP 200 with a truncated result — the pipeline cannot tell it's incomplete. Long recordings are auto-routed to `whisper-1` (chunks internally, no truncation) above the configured duration threshold. Source audio is retained on disk as a recovery net (the WAV was previously deleted on success). → `docs/stt-design-decisions.md`

**Hypr.activeToplevel null on fresh start** — The Wayland activation guard in `Hypr.qml` may filter out the active toplevel at shell startup before the `activated` protocol event arrives. Fall back to raw `Hyprland.activeToplevel` when you only need Hyprland window identity (address, class, PID) rather than confirmed Wayland activation. → `docs/qml-pitfalls.md`

**Layer-shell focus restoration race** — A layer-shell window with `WlrKeyboardFocus.Exclusive` triggers focus restoration on unmap (wlroots restores whoever held focus before the layer mapped). Synchronous `focuswindow` dispatches lose to the restoration. Always `hide()` first, then `Qt.callLater(() => Hypr.dispatch(...))`. Dispatchers that don't require an active focus target (e.g. `killwindow`) are unaffected. → `docs/qml-pitfalls.md`

**Electron tray icons are unthemeable from QML** — Discord, Heroic, Altus, and other Electron apps all register with SNI id `chrome_status_icon_1` and ship embedded pixmap bytes (no file path). They are indistinguishable from each other at the QML layer because `SystemTrayItem` exposes neither bus name nor PID. Do NOT attempt to auto-theme them via id heuristics — it cannot work. Users must override via `iconSubs` or live with the raw pixmap. → `docs/tray-icon-theming.md`

**Property contract drift across containers** — If a child exposes a property whose value a parent reads in layout calculations (e.g. `Notification.nonAnimHeight` read by `Content.qml` to size the popup stack), that property has an external contract. Refactoring its semantics inside the child (e.g. "moving margins out for cleaner math") silently under-allocates the parent — visible as last-in-stack body clipping. Grep the whole codebase for that property name to find all consumers before changing its semantics; add a comment on or immediately above the property declaration stating the contract, e.g. `// CONTRACT: nonAnimHeight = full card height including margins (read by Content.qml stack)`. → `docs/qml-pitfalls.md`

**Repeater over a rebuilt JS array resets all delegates** — A `Repeater` whose `model:` is a plain JS array cannot diff updates: every reassignment is a full reset (all delegates destroyed + recreated). When the array is re-parsed each update (e.g. bridge snapshots) and the delegate animates, frequent updates flash transient/wrong state onto unchanged siblings. Symptom: idle agent chips animated "busy" whenever an OpenCode sibling churned. Fix: wrap in `ScriptModel { values: <array>; objectProp: "id" }` (`"id"` is the agent-chip key; use whatever property is the stable unique key in your model) to key delegates on a stable id so they update in place. Use this for any animated Repeater bound to a rebuilt array. → `docs/qml-pitfalls.md`

**A Repeater delegate's `parent` is null in its first binding pass** — the delegate is instantiated before it is reparented, so a bare `parent.<prop>` in the **delegate root** throws a TypeError on every creation. No visual symptom (the binding re-evaluates on reparent), just a steady drip of log noise that buries real warnings. Use `parent?.<prop>` — but only on the delegate root; items nested inside it already have a parent. → `docs/qml-pitfalls.md`

**`Component.onCompleted` in a singleton needs `import QtQuick`** — Quickshell's own modules do not bring `Component` into scope. A data-only singleton never needed `QtQuick`, so the import only becomes necessary the moment someone adds a lifecycle hook — and Quickshell resolves the whole singleton graph at startup, so the unresolvable attached object means **the shell does not start at all**. The error is ~35 lines of unrelated `Type X unavailable` with the real cause on the last line; read it bottom-up. `qmllint` DOES report this (as `unresolved-type` on the `Component.onCompleted` line) once run correctly — but both categories involved still carry a backlog and sit at `info`, so it does not fail the build yet. A singleton change is still unverified until the shell has actually been restarted. → `docs/qml-pitfalls.md`, `docs/qmllint-setup.md`

**A `ShapePath` that ends on a near-zero segment renders NOTHING** — when a closed path's final point is computed by two different pieces of code (e.g. `PathAngleArc` derives its own start while the closing `PathLine` respells that corner with `cos`/`sin`), the two agree only to a float epsilon and the path ends on a ~1e-15 segment. `Shape.CurveRenderer` does not skip it — it emits nothing for the **whole path**, so the shape vanishes. It looks like a random one-frame flicker but is deterministic per value. Rule: every corner comes from ONE expression, read by everything that needs it. Critically, the obvious test **misses it**: building N instances and grabbing each once exercises only the first tessellation. Step ONE instance and diff each frame against its neighbours. → `docs/qml-pitfalls.md`

**`ShaderEffect` binds uniforms BY NAME** — renaming a QML property without renaming it in the shader's `buf` block silently leaves the uniform zero-initialised; no error, and `status == Compiled`. Same silent-render class: a missing or stale `.qsb` draws nothing at all, and headless rendering without `QT_QUICK_BACKEND=rhi` falls back to the software renderer, which also draws `ShaderEffect` as nothing. → `docs/qml-pitfalls.md`

**A derived property reads STALE inside a change handler that fires upstream of it** — inside `onXChanged`, any binding depending on `X` (`readonly` or not) may not have re-evaluated yet, so `onRunningChanged` observes `remainingSeconds` still holding its pre-change value. A handler must re-derive its verdict from raw state, never from another binding. And never write a binding's dependency from the change handler of the property that binding computes — here, writing `props.deadlineMs` from `onRunningChanged` when `running` derives from it: Qt aborts that as a binding loop (logged as `Binding loop detected for property "X"` — grep `qs log` for it whenever a property looks stuck) and leaves the property **frozen at its stale value**, a corrupted property rather than a mere warning. Defer the write with `Qt.callLater`. Symptom: `services/SuspendTimer.qml` suspended the machine the instant the toggle was armed, then read as "armed, 0:00" forever. → `docs/qml-pitfalls.md`

**`readonly property` blocks ALL assignment** — `readonly` in QML means the property has ONE value source (its initializer) and forbids imperative assignment from *any* scope, including signal handlers in the same file — there is no "internal write" exception. Any property written imperatively by an internal `FileView`/`Process`/`Timer` handler must stay a plain writable `property`; marking it `readonly` makes the handler's assignment silently no-op, freezing the value. `qmllint` DOES catch this and now fails the build on it — `ReadOnlyProperty` is at `error` in `.qmllint.ini`, verified by reproducing the regression. Symptom: `QuietMode.enabled` made `readonly` by a code review → `FileView.onLoaded` write failed → Silent toggle frozen false. → `docs/qml-pitfalls.md`, `docs/qmllint-setup.md`

**A `Component`-typed default property turns children into templates** — most containers default to `data` / `list<QObject>`, but some declare a `QQmlComponent` default property, and then EVERY child written inside is implicitly wrapped in a `Component`: it becomes a template the parent instantiates on its own terms, never a live sibling in this file, and its `id` is invisible to the enclosing file. The slot is also not a list, so a second child silently overwrites the first — with no error at all. `WlSessionLock`'s default property is `surface` (a `QQmlComponent`), so a `Timer` declared inside it never ran (`LockSurface` took the slot) and `onUnlock` threw `ReferenceError: <id> is not defined` on every unlock — the lock's unlock-failsafe had never once executed. Only the object the parent builds per template (per-surface here; per-item or per-window elsewhere) belongs inside; move everything else out to a container whose default property accepts arbitrary children — `Scope` does. Before nesting, check the type's `defaultProperty` and that property's declared `type` in `/usr/lib/qt6/qml/Quickshell/<Module>/*.qmltypes`. Symptom: a `ReferenceError` in `qs log` for an id plainly visible a few lines above — suspect a component-scope boundary, not a typo. → `docs/qml-pitfalls.md`

## Deep Dives

Detailed documentation in `docs/` — read on-demand when working on specific areas:

**Architecture & Extension:**
- [`drawer-extension-guide.md`](docs/drawer-extension-guide.md) — Panel backgrounds, bar pill pattern, FocusManager usage
- [`ags-porting-reference.md`](docs/ags-porting-reference.md) — AGS bar features to port (workspace icons, updates, Kanata, submap)
- [`beams-background.md`](docs/beams-background.md) — Read before touching the lock screen background, `Config.lock.beams`, or any `ShaderEffect`: shader calibration, the reveal-timing normalisation, `.qsb` recompilation, and headless iteration

**Pitfalls & Research:**
- [`qml-pitfalls.md`](docs/qml-pitfalls.md) — All QML gotchas consolidated
- [`qmllint-setup.md`](docs/qmllint-setup.md) — Read before running qmllint, editing `.qmllint.ini`, or touching the Lint workflow: the two silent traps (wrong binary, unresolved `qs.*`), the ratchet policy, and why some categories stay disabled
- [`cursor-shape-layer-shell.md`](docs/cursor-shape-layer-shell.md) — Cursor shape behavior in Wayland layer-shell
- [`tray-icon-theming.md`](docs/tray-icon-theming.md) — Icon resolution pipeline, Electron SNI limitation, Option C future path
- [`module-setup.md`](docs/module-setup.md) — External prerequisites for Askpass, Clipboard, STT, Calculator, KeyChords

**STT:**
- [`stt-design-decisions.md`](docs/stt-design-decisions.md) — Pipeline design rationale and historical bugs
- [`stt-drawer-animation.md`](docs/stt-drawer-animation.md) — Show animation stutter: root cause, fix, and QML polish lifecycle
- [`PRD-stt-system.md`](docs/PRD-stt-system.md) — Original product requirements
- [`stt-future-work.md`](docs/stt-future-work.md) — Planned improvements

**Investigations:**
- `*.investigation.md` files — Debug session logs for past issues
- [`agent-state-diagnostics.md`](docs/agent-state-diagnostics.md) — Hook → bridge → QML pipeline, stuck-state watchdog, SIGUSR1 dump, `agentbar diagnose` IPC

## Updating from Upstream

```bash
git fetch upstream
git checkout main
git merge upstream/main    # Or: git rebase upstream/main
```

The `base` branch tracks `upstream/main`, so after fetch you can compare: `git diff base..main`.
