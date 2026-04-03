# Profiling Methodology

## The Heartbeat Technique

The most reliable way to measure startup responsiveness is a QML Timer heartbeat. Add this to `shell.qml` inside the `ShellRoot`:

```qml
// Temporary startup profiler — add inside ShellRoot {}
Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())
Timer {
    interval: 500; running: true; repeat: true; property int b: 0
    onTriggered: {
        b++;
        console.log("[BOOT:HB] #" + b + " @ " + Date.now());
        if (b >= 10) running = false;
    }
}
```

**How to interpret:**
- If beat #1 arrives at ~+500ms → startup is instant (event loop responsive)
- If beat #1 arrives at ~+18000ms → event loop was frozen for 18 seconds

**Test procedure:**
```bash
pkill -f "qs -c symmetria$"
sleep 2
rm -rf ~/.cache/quickshell/qmlcache   # Cold cache — worst case
qs -c symmetria &>/dev/null &; disown
sleep 25
qs log -c symmetria -n 2>&1 | grep "\[BOOT"
```

**With warm cache (no cache clear):**
```bash
pkill -f "qs -c symmetria$"
sleep 2
qs -c symmetria &>/dev/null &; disown
sleep 25
qs log -c symmetria -n 2>&1 | grep "\[BOOT"
```

## Per-Service Timing

For granular timing of individual services and modules, add `console.log("[BOOT] <Name> @ " + Date.now())` to each `Component.onCompleted` handler. The absolute timestamps can be sorted to create a timeline waterfall. See `06-test-results.md` for an example output.

## System Call Tracing

For deeper analysis, strace can reveal what the process is doing during the freeze:

```bash
strace -T -e trace=poll,ppoll,futex -o /tmp/qs-strace.log -f qs -c symmetria
```

Key findings from strace:
- Main thread (PID from first line) does ~1661 `ppoll` calls with 90ms timeout during the freeze
- Render threads blocked in `futex` for 15-20 seconds
- The main thread IS entering the event loop but no events arrive (all polls return Timeout)
- This proves the event loop is running but QML compilation work happens synchronously between poll iterations

## SceneGraph Debug

```bash
QSG_INFO=1 qs -c symmetria &>/tmp/qs-scenegraph-debug.log 2>&1
```

Reveals: 9 OpenGL contexts created (one per window), each loading pipeline cache from `~/.cache/quickshell/qtpipelinecache-*/qqpc_opengl` (148KB). EGL context creation itself is fast (~1ms each) — not the bottleneck.

## Benchmarking External Commands

Commands called during startup and their wall-clock times on this system:
- `nmcli dev wifi list`: **5.08 seconds** (WiFi scan)
- `curl ipinfo.io/json`: **1.08 seconds** (geolocation)
- `ddcutil detect --brief`: **0.64 seconds** (display detection)
- `which cliphist`: **<1ms**
- `asdbctl get`: **<1ms** (not installed, instant fail)

These are all async (non-blocking) — they complete during the 18s freeze but their callbacks can't fire until the event loop unblocks.
