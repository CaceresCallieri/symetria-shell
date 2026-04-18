---
name: Orchestrator remote reload
description: How to reload orchestrator.nvim across all running NeoVim instances via RPC sockets
type: reference
originSessionId: 3aabc515-5969-41e2-bf63-cc26a3f49375
---
After changing orchestrator.nvim code, reload it in ALL running NeoVim instances at once:

```bash
for sock in /run/user/$(id -u)/nvim.*.0; do
  nvim --server "$sock" --remote-expr 'luaeval("require(\"orchestrator\").reload()")' 2>/dev/null
done
```

This uses NeoVim's built-in RPC server sockets at `/run/user/$UID/nvim.*.0`. The `--remote-expr` flag evaluates an expression in the target instance synchronously.

The agent bridge already uses this same pattern (`solicit_neovim_instances()` in `agent-bridge.py`) to trigger `bridge.reconnect()` on startup.

Also documented in the orchestrator's own `CLAUDE.md` under Development Commands.
