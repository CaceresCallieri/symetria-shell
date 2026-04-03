# Module Setup Prerequisites

External dependencies and configuration that can't be discovered from reading the QML source code.

## Askpass (sudo Password Prompt)

Provides a native password prompt for `sudo -A` operations.

**Setup:**
```bash
# Add to ~/.zshrc
export SUDO_ASKPASS="$HOME/.dotfiles/scripts/symmetria-askpass.sh"
```

**How it works:** When `sudo -A` is invoked, it runs the script, which creates a secure FIFO and triggers the shell popup via IPC. Password never touches disk (FIFO exists only in kernel memory, 600 permissions).

**IPC:** `qs -c symmetria ipc call askpass prompt "<message>" "<fifo_path>"`

## Clipboard Manager

**Prerequisites:**
```bash
paru -S cliphist wl-clipboard
```

**Hyprland config:**
```conf
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
```

**IPC:** `qs -c symmetria ipc call drawers toggle clipboard`

**Note on search:** Config has `useFuzzy: false`. With fuzzy enabled, matched items may not show highlights (FZF matches non-contiguous characters but highlighting uses substring).

## Speech-to-Text (STT)

**Prerequisites:**
- `pipewire` (pw-record) — already installed on PipeWire systems
- `curl` — for OpenAI API calls
- `wl-clipboard` (wl-copy) — for clipboard delivery
- `ffmpeg` — optional, for pause/resume segment concatenation

**API Key:** Set `OPENAI_API_KEY` env var or `stt.apiKey` in `~/.config/symmetria/shell.json`.

**Design decisions:** See `docs/stt-design-decisions.md` for critical architectural rationale.

## Calculator

No external setup needed — `libqalculate` is provided via the C++ plugin.

**Launcher integration:** Type `>calc 2+2` in the launcher to open the calculator with the expression pre-filled.

**IPC:** `qs -c symmetria ipc call drawers toggle calculator`

## KeyChords (Which-Key Overlay)

**Configuration file:** `~/.config/symmetria/chords.json` (see `chords.example.json` for schema)

```json
{
  "groupName": {
    "title": "Display Title",
    "chords": [
      { "key": "x", "label": "Description", "command": "shell command" }
    ]
  }
}
```

**Validation:** `key` = single character, `label` + `command` = non-empty strings. Invalid groups are silently skipped. File is hot-reloaded on changes.

**Security:** Commands execute via `sh -c` without sanitization. Trusted at the same level as `~/.bashrc`.

**IPC:** `qs -c symmetria ipc call chords activate <groupName>`
