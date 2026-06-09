# Lock-screen crash observability

Instrumentation around Symmetria's lock-screen lifecycle so that the *next*
"lock armed but undrawn" episode (most often around suspend → resume) leaves
diagnostic data instead of being an unrecoverable mystery.

## The key fact that shaped this design

Symmetria does **not** use `hyprlock`. The lock screen is Symmetria's **own
in-process `WlSessionLock` surface** (`modules/lock/Lock.qml` +
`LockSurface.qml`), triggered by `modules/IdleMonitors.qml`. `hypridle` and the
old `run_hyprlock_with_random_wallpaper.sh` wrapper are **inert** on this system
(hypridle is disabled in `~/.config/hypr/startup.conf`), so the stale
`~/.hyprdots/...hyprlock.conf` path in that wrapper is a **red herring** for this
crash — it never executes. (Cleaning up that wrapper is a separate dotfiles-side
hygiene task, not a fix for this.)

Forensics on a real episode (2026-06-07) showed the `qs` shell **alive the whole
time** (4h+ uptime across three resumes) with **no coredump in 6+ weeks**. So the
failure is almost certainly **not a process crash**. The lock surface is
`color: "transparent"`; its only opaque content is a live, blurred
`ScreencopyView` of the screen. Hyprland removes/re-adds outputs across
suspend/resume, and `WlSessionLockSurface` is per-output — so on resume the
surface is recreated while the capture source churns. If the recreated
`ScreencopyView` never gets a frame, the lock is a transparent sheet over the
compositor's blank session-lock fallback: **armed but undrawn, qs still alive**.

That inverts the usual "supervise the locker process" approach: the highest-value
vantage point is **in-process** (qs survives and can self-report why the surface
is blank), with an **external watchdog** as the backstop for the cases qs cannot
report (true qs death, or a wedge that never recovers).

## What was added

### 1. In-process logger — `services/LockDiagnostics.qml` (singleton)

Append-only JSON-lines timeline + a liveness heartbeat. Every method is
fire-and-forget and exception-guarded; a logging fault can never block
lock/unlock. Writes go through `Quickshell.execDetached` (base64-encoded to dodge
shell-quoting), never synchronously.

Wired into:
- `modules/IdleMonitors.qml` — idle actions (`idle_action`), `about_to_sleep`,
  and **`resume`** (via `LogindManager.resumed()`, a signal nothing previously
  used — it anchors `sinceResumeMs` on every later event).
- `modules/lock/Lock.qml` — mirrors the real `WlSessionLock.locked` via
  `onLockedChanged` (single source of truth) and annotates the reason
  (shortcut/IPC/idle/sleep/logind).
- `modules/lock/LockSurface.qml` — per-screen `surface_created`/`surface_destroyed`
  and the **`screencopy` hasContent** transitions (the blank-capture smoking gun).
- `modules/lock/Pam.qml` — `pam_attempt` / `pam_result` (success/fail/max/error)
  for password and fingerprint.

### 2. External watchdog — `scripts/lock-watchdog.py` + systemd user service

Independent of `qs` (so it survives a shell crash). Tails the heartbeat and
flags a stuck lock when, **while locked**: the heartbeat mtime goes stale
(qs dead / event loop stalled), the recorded pid dies, or `screencopyHealthy`
stays false too long (wedged blank surface). On a verdict it appends a
`watchdog_stuck` event and best-effort `notify-send`s. It does **not**
auto-recover — recovery is still the manual `recover` alias from a TTY.

Boot-safety: it only alarms for a wedge it watched go live-then-bad, so a
leftover `locked:true` heartbeat from a prior crash can't false-alarm on boot.

## Where the data lives

```
~/.local/state/symmetria/lock/
├── lifecycle.jsonl   # append-only event timeline (rotated at 1 MiB -> .jsonl.1)
└── heartbeat         # latest liveness snapshot (rewritten every 2s while locked)
```

### Event types (`type` field)

| type | source | meaning |
|------|--------|---------|
| `logger_init` | qs | shell started, logger initialized |
| `idle_action` | qs | idle/return action fired (`action`, `edge`) |
| `about_to_sleep` | qs | logind PrepareForSleep=true (`lockedAtSleep`) |
| `resume` | qs | logind PrepareForSleep=false (`stillLocked`, `screencopyHealthy`) |
| `lock_engaged` / `lock_released` | qs | real locked transition (`reason`) |
| `surface_created` / `surface_destroyed` | qs | per-output lock surface (`screen`) |
| `screencopy` | qs | background capture `hasContent` flipped (`screen`, `hasContent`) |
| `pam_attempt` / `pam_result` | qs | auth attempt / outcome (`method`, `result`) |
| `unlock_requested` | qs | explicit unlock via shortcut/IPC (`source`) |
| `watchdog_started` | watchdog | watchdog came up |
| `watchdog_stuck` | watchdog | **stuck lock detected** (`reason`, `lockedPid`, `pidAlive`, `heartbeatAgeMs`, `screencopyHealthy`, `surfaces`) |
| `watchdog_recovered` / `watchdog_cleared` | watchdog | wedge resolved / session unlocked |

Post-resume events also carry `sinceResumeMs` — the field most likely to expose
suspend/resume clustering.

## On the next crash: how to read it

1. From a TTY, before running `recover`, grab the timeline:
   ```bash
   tail -n 50 ~/.local/state/symmetria/lock/lifecycle.jsonl
   cat ~/.local/state/symmetria/lock/heartbeat
   ```
2. Hand that to an agent. The decisive questions the data now answers:
   - Was there a `resume` event, and what is `sinceResumeMs` on the failure?
   - Did `screencopy` ever reach `hasContent: true` after the last
     `surface_created` (per screen)? **If it stayed false → blank-capture
     confirmed.**
   - Did the watchdog log `watchdog_stuck`, and with what `reason`
     (`screencopy_blank` vs `heartbeat_stale`/`qs_dead`)?
   - Correlate against `journalctl --user -b` and `coredumpctl list` for the
     timestamp (a coredump would mean a real process crash instead).

## Manual capture: `scripts/lock-crash-snapshot.sh`

The automated detection has structural blind spots (below). The most reliable
signal is a human who *knows* it just crashed. Run this the instant it happens —
it works from a TTY (Ctrl+Alt+F2) even when the GUI is wedged, and it captures
*before* `recover` wipes the evidence:

```bash
~/.config/quickshell/symmetria/scripts/lock-crash-snapshot.sh "what you saw"
```

It appends a `user_marked_crash` marker to `lifecycle.jsonl` and writes
`crash-snapshot-<ts>.txt` containing: qs/hyprlock liveness, watchdog status,
`allow_session_lock_restore`, loginctl session, **`hyprctl monitors`** (output
state — the output-churn theory), the heartbeat, the last 80 lifecycle events,
coredumps today, the kernel suspend/resume timeline, and the recent qs/lock
journal. Hand that file to an agent. Recommended: alias it (`alias lockcrash=...`)
or call it from the top of `recover-lockscreen.sh` so every recovery auto-captures.

## Known blind spots (why the manual capture exists)

- **Pre-lock failure** — if `WlSessionLock` never *engages* (client dies during
  acquisition), no heartbeat is ever written, so the watchdog reads "clean" and
  cannot see it. Manual snapshot covers this.
- **Mild / self-healing modes** — a brief black draw that recovers on its own
  won't sustain `screencopyHealthy:false` past `UNHEALTHY_SECS`, so no alarm.
- **The restart gap** — the in-process logger only runs after `qs` is restarted
  with the instrumented code. A crash before that restart captures nothing
  in-process (only the journal/coredump trail).
- **`loginctl LockedHint` is unreliable here** — Symmetria's `WlSessionLock` does
  not set logind's LockedHint (observed `no` even while locked), so it is NOT a
  trustworthy "is locked" signal. It's captured for completeness only.

## Operating the watchdog

```bash
systemctl --user status  symmetria-lock-watchdog.service
journalctl --user -u symmetria-lock-watchdog.service -f
systemctl --user disable --now symmetria-lock-watchdog.service   # turn off
```

Thresholds are env-overridable (set in the unit's `[Service]` with `Environment=`):
`SYMMETRIA_LOCK_WD_POLL_SECS` (2), `SYMMETRIA_LOCK_WD_STALE_SECS` (8),
`SYMMETRIA_LOCK_WD_UNHEALTHY_SECS` (12).

The unit is version-controlled at
`assets/systemd/symmetria-lock-watchdog.service` and symlinked into
`~/.config/systemd/user/`.

## Sharper root-cause lead: Hyprland hibernate-image lock persistence

Hyprland discussion #13184 ("Session lock state persists through hibernate
causing broken lockscreen on resume") describes this exact symptom as a
**compositor-level** issue, not a Symmetria bug:

- The ext-session-lock state lives in Hyprland's memory. **Hibernation** writes
  the whole memory image to disk; on resume Hyprland restores the "locked" flag
  from the image, but the lock surface / output / GPU linkage does not survive
  intact → armed but undrawn.
- A maintainer's key statement: **"The only way to unlock a proper Wayland
  compositor is for the locking app to be unlocked."** That is exactly what the
  `recover` script's primary path does — `qs ... ipc call lock unlock` releases
  Symmetria's own `WlSessionLock`. There is no external force-unlock.
- `allow_session_lock_restore` was observed to itself be restored from the image
  (reads `1` even when configured `false`), i.e. it is not consulted fresh on
  resume.

**Why this fits here:** the idle config runs `systemctl suspend-then-hibernate`
(900s). That suspends (s2idle) immediately and escalates to **hibernate** after
`HibernateDelaySec` (systemd default — no override in `/etc/systemd/sleep.conf`).
Plain s2idle resumes have been observed to unlock fine; the intermittent wedge
most likely corresponds to the rarer **actual hibernate** resumes. Confirm on the
next crash via the snapshot's kernel-timeline section (look for
`PM: hibernation` / `Entering sleep state disk`, not just `PM: suspend`).

## Likely fix directions (once data confirms)

Not implemented — this is observability only. Candidates, best-first:

1. **Re-lock on resume.** On `LogindManager.resumed()`, if `lock.locked`, release
   and immediately re-acquire the `WlSessionLock` (toggle `locked` false→true in
   the same tick) so a fresh, correctly-drawn surface replaces the broken one.
   Keeps the locked-on-resume security guarantee; the reveal window is a single
   event-loop tick. This is the most direct counter to the #13184 mechanism.
2. **Avoid hibernate.** Change the 900s idle action from `suspend-then-hibernate`
   to plain `suspend` (shell.json), or set a long `HibernateDelaySec`. Sidesteps
   the hibernate-image bug entirely at the cost of no hibernation.
3. **Opaque fallback background** in `LockSurface.qml` so a missing
   `ScreencopyView` frame degrades to a solid/blur instead of a transparent
   (invisible) lock — mitigation, not a cure.
4. **Auto-recover** — have the watchdog run the `recover` IPC-unlock on a
   confirmed stuck verdict (was an explicit non-goal; revisit if the wedge proves
   frequent).
