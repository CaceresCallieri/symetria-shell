---
name: cli-redeploy-cp-rt-gotcha
description: "symmetria-cli redeploy must use `cp -rT` — plain `cp -r` fails SILENTLY (nests, leaves the imported package stale)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 661d872b-0de8-43b6-80cf-a0e21006e2d3
---

Redeploying `symmetria-cli` to site-packages must use `cp -rT` (the `-T` is
mandatory). The destination `/usr/lib/python3.14/site-packages/symmetria/`
already exists, so the documented-at-the-time `cp -r src dest` copied *into* it,
creating a dead nested `symmetria/symmetria/` and **silently** leaving the
real top-level package — the one Python imports — untouched.

**Why it's a trap:** there is NO error. The copy "succeeds," but your CLI edits
never take effect, so the next run uses the old code and you chase a phantom
"my change didn't work" bug. Verify a redeploy with
`grep <your-change> /usr/lib/python3.14/site-packages/symmetria/<file>`.

The fix is now documented in the project CLAUDE.md (CLI section) — this note
exists to surface the *silent-failure* nature proactively each session.
Related: [[feedback_always_clear_cache]] (the analogous "did my change land?"
trap on the QML side).
