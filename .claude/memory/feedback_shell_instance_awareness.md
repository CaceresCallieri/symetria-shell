---
name: Always check for running shell before launching test instances
description: Before running any qs command that creates windows, verify no conflicting Quickshell instance is already running. Layer-shell windows will conflict.
type: feedback
---

Before launching `qs -c <config>` for any config that creates layer-shell windows (Drawers, Background, OSD, etc.), always check if a Quickshell instance with conflicting windows is already running. Use `pgrep -f "qs -c"` or check `/run/user/1000/quickshell/by-id/`. Import-only tests (no component creation) are safe to run alongside, but anything that instantiates visual components will conflict.

**Why:** The user had to manually kill the running shell because the benchmark tried to create duplicate layer-shell windows.
**How to apply:** Before any `qs -c` test that creates components, run `pgrep -f "qs "` and warn/confirm if an instance is active.
