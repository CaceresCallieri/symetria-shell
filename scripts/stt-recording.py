#!/usr/bin/env python3
"""Fire-and-forget STT recording-state push to a Symmetria IDE's agent socket.

Part of the agent-ownership inversion (Phase 4, pure-direct STT): the shell no
longer routes the recording soundwave through agent-bridge.py's snapshot `stt`
field. Instead AgentService spawns this helper to tell the OWNING IDE directly
to light (or clear) the recording dot on a specific agent chip.

The IDE listens on ``$XDG_RUNTIME_DIR/symmetria-ide-agents-<ide_pid>.sock`` and
interprets ``{"type":"stt_recording","buf":int,"transcribing":bool}`` where buf
is the agent slot, -1 = the focused agent, and 0 (or any unknown slot) = clear
(see AppController._on_stt_recording). This is best-effort: a missing/dead IDE
socket is a silent no-op (matching the old "write to a dead hub is a no-op"
semantics), because the chip dot is a cosmetic mirror — the shell's own agentbar
reads local AgentService state and is unaffected either way.

Usage: stt-recording.py <ide_pid> <buf> <transcribing 0|1>
Always exits 0 — a delivery failure must never disrupt the recording flow.
"""

import json
import os
import socket
import sys


def main() -> int:
    if len(sys.argv) != 4:
        return 0  # malformed call — nothing to do, stay silent
    try:
        ide_pid = int(sys.argv[1])
        buf = int(sys.argv[2])
    except ValueError:
        return 0
    transcribing = sys.argv[3] == "1"
    if ide_pid <= 0:
        return 0  # non-IDE / remote agent — no direct socket to reach

    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    path = os.path.join(runtime, f"symmetria-ide-agents-{ide_pid}.sock")

    msg = {"type": "stt_recording", "buf": buf, "transcribing": transcribing}
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(1.0)
    try:
        sock.connect(path)
        sock.sendall((json.dumps(msg) + "\n").encode())
    except OSError:
        pass  # IDE gone / socket missing — best-effort, stay silent
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
