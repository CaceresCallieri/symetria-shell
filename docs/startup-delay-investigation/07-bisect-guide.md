# Git Bisect Guide for Startup Delay Regression

## Theory

The user doesn't remember the startup being this slow before the agent dashboard implementation. This suggests the delay is a **regression** introduced by a specific commit or series of commits — likely one that added a heavy import chain (controlcenter, Quickshell.Services.Notifications, etc.).

## Bisect Strategy

### Setup

```bash
# Get commit range
git log --oneline | head -50  # find the "good" commit (before agent dashboard)

# Start bisect
git bisect start
git bisect bad HEAD                    # current state is bad (18-20s)
git bisect good <commit-before-agentbar>  # pick a commit you know was fast
```

### Test Script

Create `~/.config/quickshell/symmetria/scripts/bisect-test.sh`:

```bash
#!/bin/bash
# Returns 0 (good) if startup < 5s, 1 (bad) if >= 5s

# Add heartbeat profiler if not already present
if ! grep -q "BOOT:HB" shell.qml; then
    # Inject profiler into shell.qml after ShellRoot {
    sed -i '/^ShellRoot {/a\    Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())\n    Timer { interval: 500; running: true; repeat: true; property int b: 0; onTriggered: { b++; console.log("[BOOT:HB] #" + b + " @ " + Date.now()); if (b >= 10) running = false; } }' shell.qml
fi

# Kill existing, clear cache, start fresh
pkill -f "qs -c symmetria$" 2>/dev/null
sleep 2
rm -rf ~/.cache/quickshell/qmlcache
qs -c symmetria &>/dev/null &
QS_PID=$!

# Wait for startup (max 25 seconds)
sleep 25

# Extract heartbeat timing
BOOT_TS=$(qs log -c symmetria -n 2>&1 | grep -m1 "\[BOOT\] ShellRoot" | grep -oP '@ \K[0-9]+')
HB1_TS=$(qs log -c symmetria -n 2>&1 | grep -m1 "\[BOOT:HB\] #1" | grep -oP '@ \K[0-9]+')

# Kill shell
pkill -f "qs -c symmetria$" 2>/dev/null
sleep 1

# Revert profiler injection
git checkout -- shell.qml 2>/dev/null

if [ -z "$BOOT_TS" ] || [ -z "$HB1_TS" ]; then
    echo "SKIP: Could not extract timing (build failure?)"
    exit 125  # bisect skip
fi

DELAY=$(( HB1_TS - BOOT_TS ))
echo "Startup delay: ${DELAY}ms"

if [ "$DELAY" -lt 5000 ]; then
    echo "GOOD: Startup under 5 seconds"
    exit 0
else
    echo "BAD: Startup over 5 seconds (${DELAY}ms)"
    exit 1
fi
```

### Run Bisect

```bash
chmod +x scripts/bisect-test.sh
git bisect run scripts/bisect-test.sh
```

### Important Notes

1. **Clear QML cache at each step** — the script does this, but verify
2. **C++ plugin changes** — some commits may change C++ code. The bisect script should detect build failures (exit 125 = skip)
3. **Config file compatibility** — older commits may expect different shell.json structure. If the shell fails to start, the script returns 125 (skip)
4. **The delay may not be a single commit** — it could be gradual (each import added a few files). In that case, bisect will find the commit that pushed it over the threshold

## What To Look For

The bisect will likely land on a commit that:
- Added `import qs.modules.controlcenter` somewhere in the eager path
- Added `import Quickshell.Services.Notifications` or `Quickshell.Widgets`
- Added a new module directory with many files
- Moved a type to a directory that's eagerly scanned

## Key Commits to Investigate

Based on the user's suspicion, the agent dashboard implementation is the primary suspect. The agentbar module has 9 files and imports `qs.services` + `qs.config` — relatively lightweight. But if the agent dashboard added the **controlcenter** module or restructured imports, that could be the trigger.

Also look for commits that:
- Added the `modules/controlcenter/` directory (49 files!)
- Added `import qs.modules.controlcenter` to Shortcuts.qml or bar/popouts/Wrapper.qml
- Added `Quickshell.Services.Notifications` import to any eagerly-loaded file

## Manual Bisect (Alternative)

If the automated bisect is unreliable, do it manually:

1. `git log --oneline | wc -l` → get total commit count
2. `git checkout HEAD~N` (where N is half the count)
3. Clear cache, add heartbeat, test
4. If fast: the regression is in the newer half
5. If slow: the regression is in the older half
6. Repeat until you find the specific commit

The heartbeat technique is fast and reliable — just check if beat #1 is at +500ms or +18000ms.
