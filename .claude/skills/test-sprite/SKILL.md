---
name: test-sprite
description: Preview SVG sprite animations in the agentbar (bottom bar). Use when the user wants to test, preview, or visually inspect a sprite animation, icon, or morph sequence. Invoke with /test-sprite.
allowed-tools: "Read,Write,Edit,Bash(rm -rf ~/.cache/quickshell/qmlcache:*),Bash(qs:*),Bash(ls:*),Bash(sleep:*)"
---

# Test Sprite Preview

Display SVG sprite animations in the agentbar (bottom bar), right-aligned, for visual testing.

## How It Works

The agentbar contains a persistent `SpritePreview.qml` component. This skill edits its properties, clears the QML cache, and restarts the shell. The agentbar appears even without connected agents when the preview is active.

**Preview file:** `~/.config/quickshell/symmetria/modules/agentbar/SpritePreview.qml`

## Usage

Arguments are passed after `/test-sprite`. Parse them to determine what to do:

| Command | Action |
|---------|--------|
| `/test-sprite <mode>` | Preview a ClaudeSparkle mode (e.g., `key-morph`, `working`, `stt-wave`) |
| `/test-sprite <mode1> <mode2>` | Chain two modes (e.g., `starting key-morph` for emerge → morph) |
| `/test-sprite stop` | Disable the preview |

### Optional flags (parse from args)

| Flag | Default | Description |
|------|---------|-------------|
| `--speed <n>` | `1.0` | Speed multiplier (e.g., `0.5` for half speed, `2.0` for double) |
| `--hold <ms>` | `1200` | Pause in ms before restarting one-shot animations |

## Valid ClaudeSparkle Modes

| Mode | Frames | Behavior | Sprite Asset |
|------|--------|----------|-------------|
| `working` | 8 | Loops | `claude-sparkle-sprite` |
| `thinking` | 9 | Loops | `claude-sparkle-thinking-sprite` |
| `starting` | 9 | One-shot | `claude-sparkle-starting-sprite` |
| `stopping` | 12 | One-shot | `claude-sparkle-stopping-sprite` |
| `stt-morph` | 12 | One-shot | `claude-sparkle-stt-morph-sprite` |
| `stt-wave` | 12 | Loops | `claude-sparkle-stt-wave-2-sprite` |
| `key-morph` | 12 | One-shot | `claude-sparkle-key-morph-sprite` |

Looping modes cycle automatically. One-shot modes play once, hold at the final frame for `holdMs`, then restart from frame 0.

## Editing SpritePreview.qml

The file has clearly marked skill-managed properties. Edit ONLY these properties:

```qml
// ── Skill-managed properties ─────────────────────────────────────
property bool previewActive: false          // ← set to true/false
property string previewMode: "key-morph"    // ← primary mode
property string chainMode: ""              // ← optional second mode (empty = none)
property int holdMs: 1200                  // ← hold before restart
property real speed: 1.0                   // ← speed multiplier
// ── End skill-managed ────────────────────────────────────────────
```

Use the Edit tool to modify these properties. Do NOT rewrite the entire file.

## Restart Procedure

After editing properties, ALWAYS:

```bash
rm -rf ~/.cache/quickshell/qmlcache && qs -c symmetria kill 2>/dev/null; sleep 0.3; qs -c symmetria -d
```

Wait for "Configuration Loaded" in the output to confirm success.

## Examples

### Preview key-morph animation
Edit `previewActive: true`, `previewMode: "key-morph"`, `chainMode: ""`.

### Preview emerge → key-morph chain
Edit `previewActive: true`, `previewMode: "starting"`, `chainMode: "key-morph"`.

### Preview at half speed
Edit `previewActive: true`, `previewMode: "key-morph"`, `speed: 0.5`.

### Stop preview
Edit `previewActive: false`.

## Important Notes

- The preview forces the agentbar visible even without agents connected
- The preview is right-aligned in the agentbar, showing mode name + animated sparkle
- After testing, always run `/test-sprite stop` to clean up
- The `SpritePreview.qml` file should NOT be committed (it's a dev tool)
