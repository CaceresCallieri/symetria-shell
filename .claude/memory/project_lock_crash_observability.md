---
name: project_lock_crash_observability
description: "Lock-screen \"armed but undrawn\" crash — observability added, awaiting next crash to root-cause"
metadata: 
  node_type: memory
  type: project
  originSessionId: 85510e9b-cf89-406a-8339-98c229957637
---

Symmetria's lock screen intermittently ends up "armed but undrawn" around suspend→resume. Observability was added 2026-06-07; root-cause is **pending the next crash's captured data**.

**Critical correction to the original framing:** Symmetria does NOT use hyprlock. The lock is its own in-process `WlSessionLock` surface (`modules/lock/`), triggered by `IdleMonitors.qml`. `hypridle` + the `run_hyprlock_with_random_wallpaper.sh` wrapper (and its stale `~/.hyprdots/...` path) are **inert** — a red herring for this crash. (Wrapper cleanup is a separate dotfiles task.)

**Sharpened root cause (2026-06-08):** Hyprland discussion #13184 — ext-session-lock state is saved in Hyprland's **hibernate memory image**; on resume Hyprland restores "locked" but the surface/output/GPU linkage is broken → armed but undrawn, qs alive. Idle action is `suspend-then-hibernate` (900s); plain s2idle resumes unlock fine, so the wedge likely tracks the rarer **actual hibernate** resumes (explains intermittency). Maintainer: "the only way to unlock a Wayland compositor is for the locking app to unlock" → confirms the recover script's IPC-unlock path is the protocol-correct recovery. Best fix candidate: re-lock on `resumed()` (toggle locked false→true to recreate a drawn surface); or drop hibernate; or opaque LockSurface fallback.

**Recover script** (`~/scripts/recover-lockscreen.sh`, dotfiles) was rewritten to match: primary path `qs ipc call lock unlock` (works because qs is alive); fallback (qs dead) = allow_session_lock_restore + relaunch qs + hyprlock adopts orphaned lock. GAP: a HUNG qs (IPC-unreachable but alive, still holding lock) falls to the fallback, spawns a 2nd qs, and hyprlock can't adopt a live lock; primary IPC call also has no `timeout` guard. Which recovery path succeeds is itself diagnostic (primary=qs-alive/blank-surface; fallback=qs-dead).

**faillock decoupled from lock screen (2026-06-09):** `assets/pam.d/passwd` no longer uses `pam_faillock` (now just `auth required pam_unix.so nullok`). WHY: faillock keeps ONE system-wide tally shared with sudo/login; unattended `sudo -A` askpass prompts (Claude's `claude-sudo-askpass-hook.sh` rewrites agent `sudo`→`sudo -A`; left unanswered while user away → "conversation failed" → faillock++) plus the odd mistype tripped deny=3 and locked the user out of their OWN screen. Decoupling = lock attempts neither read nor increment faillock; sudo/login keep it via /etc/pam.d. Lock keeps its own retry UI (Pam.qml). Applies on next lock (libpam reads file per start(), no restart). NOT a security regression worth worrying about for this threat model; IPC unlock (`recover`) bypasses PAM as the escape hatch.

**Earlier hypothesis (still a contributing factor):** blank `ScreencopyView`. `LockSurface.qml` is `color: "transparent"`; its only opaque content is a live blurred `ScreencopyView` of `root.screen`. Hyprland removes/re-adds outputs across suspend/resume; the per-output surface is recreated while the capture source churns. If the new ScreencopyView never gets a frame → transparent lock over compositor's blank fallback, **qs still alive (no coredump in 6+ weeks)**. The `screencopy` event's `hasContent` staying false proves/kills this.

**What was added** (see `docs/lock-crash-observability.md`):
- `services/LockDiagnostics.qml` singleton → JSON-lines `~/.local/state/symmetria/lock/lifecycle.jsonl` + `heartbeat`. Wired into IdleMonitors/Lock/LockSurface/Pam.
- Used the previously-unused `LogindManager.resumed()` signal for resume correlation (`sinceResumeMs`).
- `scripts/lock-watchdog.py` + `assets/systemd/symmetria-lock-watchdog.service` (enabled, symlinked into `~/.config/systemd/user/`) — external backstop, tails heartbeat, logs `watchdog_stuck`. Alerts only, no auto-recovery (by choice).

- `scripts/lock-crash-snapshot.sh "note"` — human-triggered capture (works from TTY when GUI wedged). Appends `user_marked_crash` + writes full snapshot (monitors/loginctl/journal/coredumps/heartbeat). This is the robust path — automated detection has blind spots (pre-lock failure = no heartbeat; mild self-healing modes; loginctl LockedHint is NOT reliable for WlSessionLock).

**ACTIVATION GAP (important):** in-process logging only runs after `qs` is restarted with the instrumented code. As of 2026-06-07 the user had NOT restarted (PID 958 alive since 18:55), so nothing is captured in-process yet and the watchdog idles (no heartbeat). Today's suspected crash left NO recovery trail (no hyprlock launch, no VT switch, `allow_session_lock_restore=0`, qs never restarted) — so it either self-healed or predates instrumentation. **First action next session: confirm the user restarted qs and a `heartbeat` file now exists.**

**Next crash:** run `lock-crash-snapshot.sh` (or grab `lifecycle.jsonl`+`heartbeat`) before `recover`, hand to an agent. Decisive question: after last `surface_created`, did `screencopy` reach `hasContent:true`? Likely fix if blank-capture confirmed: re-trigger ScreencopyView on `resumed()`, or give LockSurface an opaque fallback background. Setup is single-monitor (eDP-1), so it's s2idle output teardown/recreate, not multi-output.
