---
name: Kill ALL quickshell instances before benchmarks
description: Multiple qs instances cause massive resource contention (2-3x slower), contaminating all measurements
type: feedback
---

Before starting ANY QuickShell instance for testing, ALWAYS:
1. `pkill qs` — the binary is `qs`, NOT `quickshell`. Using `pkill -x quickshell` does NOTHING.
2. `sleep 2`
3. `pgrep -fa qs | grep -v grep | grep -v zsh | grep -v python | grep -v claude` to verify ZERO instances
4. Only THEN start the test instance

**Why:** The process name is `qs`, not `quickshell`. Using the wrong name caused an entire debugging session to run with 2-5 concurrent instances, producing measurements 2-4x worse than reality. Every single "clean state verified" check was a false positive.

**How to apply:** ALWAYS use `pkill qs` and `pgrep -fa qs` (filtered). NEVER use `pkill quickshell` or `pgrep quickshell`.
