# Quickshell IPC Display Filter Bug

## Summary

`qs -c symmetria ipc call ...` fails to find a running Symmetria instance due to a display connection string mismatch in Quickshell's instance resolution. The running instance registers as `wayland,wayland-1` (comma-separated) while the IPC client matches against `wayland-1` (from `$WAYLAND_DISPLAY`). The comparison fails, and `qs` reports "No running instances" even though the shell is actively running.

## Symptoms

- `qs -c symmetria ipc call <target> <function>` returns exit 255 with:
  ```
  No running instances for "/home/jc/.config/quickshell/symmetria/shell.qml"
  Dead instances:
   - <id1>
   - <id2>
  ```
- The shell IS running (visible on screen, PID alive in `ps aux`)
- `qs list -c symmetria` shows no running instances
- `qs list --all` (without `-c`) DOES show the instance as running with `Display connection: wayland,wayland-1`

## Root Cause

Quickshell's instance registration stores the display connection as a comma-separated string like `wayland,wayland-1` (visible in the binary `instance.lock` file at `/run/user/$UID/quickshell/by-id/<instance>/instance.lock`). The IPC client reads `$WAYLAND_DISPLAY` (which is `wayland-1`) and compares it against this registered string. The formats don't match, so the display filter excludes the running instance.

### Evidence

| Command | Result |
|---------|--------|
| `qs -c symmetria ipc call ...` | Fails — "No running instances" |
| `qs ipc --any-display -c symmetria call ...` | Works |
| `qs ipc --pid <PID> call ...` | Works |
| `$WAYLAND_DISPLAY` | `wayland-1` |
| Instance lock display field | `wayland,wayland-1` |

## Workaround

Use `--any-display` flag to bypass the display filter:

```bash
# Before (broken):
qs -c symmetria ipc call <target> <function> [args...]

# After (working):
qs ipc --any-display -c symmetria call <target> <function> [args...]
```

Note the argument order change: `--any-display` and `-c` must come after `ipc` but before `call`.

This is safe because `-c symmetria` already ensures we target the correct config. The display filter is only relevant when multiple instances of the same config run on different displays (not our case).

### Alternative: Target by PID

```bash
qs ipc --pid $(pgrep -f 'qs -c symmetria' | head -1) call <target> <function> [args...]
```

## Affected Scripts

| Script | Location | Fixed |
|--------|----------|-------|
| `symmetria-askpass.sh` | `~/.dotfiles/scripts/symmetria-askpass.sh` | Yes — uses `--any-display` |

Any script or keybinding using `qs -c symmetria ipc call` is potentially affected. Check Hyprland keybindings and shell scripts for this pattern.

## Diagnostic Commands

```bash
# 1. Verify the shell is actually running
ps aux | grep 'qs -c symmetria'

# 2. Check what qs sees (with vs without display filter)
qs list -c symmetria          # Broken — shows "No running instances"
qs list --all                 # Works — shows instance with display info

# 3. Inspect the instance's registered display
cat /run/user/$(id -u)/quickshell/by-id/$(ls -t /run/user/$(id -u)/quickshell/by-id/ | head -1)/instance.lock

# 4. Check for stale dead instances (can accumulate over time)
total=$(ls /run/user/$(id -u)/quickshell/by-id/ | wc -l)
echo "Total instance entries: $total (most may be stale)"

# 5. Test IPC connectivity
qs ipc --any-display -c symmetria show   # Should list all IPC targets
```

## Stale Instance Entries

Quickshell does not clean up socket directory entries for dead instances. Over time, `/run/user/$UID/quickshell/by-id/` accumulates dozens of stale directories. These are harmless but noisy (they appear in the "Dead instances" list). They are cleared on reboot (since they live in tmpfs under `/run`).

## Status

Likely a Quickshell upstream bug. The display connection format `wayland,wayland-1` vs `$WAYLAND_DISPLAY=wayland-1` suggests the server stores `<backend>,<display_name>` while the client only checks `<display_name>`. Not yet reported upstream.
