# Extracting Sprite Sheets from claude.ai

## Overview

Claude.ai uses hand-drawn SVG sprite sheets for its sparkle animations. These are single `<svg>` elements with one `<path>` containing all frames stacked vertically. The sprites are rendered inline in the DOM by React components — **not** loaded from external files or stored in JS bundles.

## Known Sprite Sheets

| Sprite | viewBox | Frames | Cycle | Used When |
|--------|---------|--------|-------|-----------|
| Working/streaming | `0 0 100 800` | 8 | 810ms (101ms/frame) | Claude is streaming a response |
| Thinking/breathing | `0 0 100 900` | 9 | 909ms (101ms/frame) | Claude is processing before streaming |

### Working Sprite (8 frames)
- All frames are full starburst variations (different ray angles/positions)
- Gives a "rotating" or "twinkling" effect
- Frame 0 is clipped in bottom-right; frame 4 is the most complete
- Local asset: `assets/claude-sparkle-sprite.svg`

### Thinking Sprite (9 frames)
- Frames morph from dot → starburst → dot (breathing cycle)
- Frame 0: tiny dot/blob
- Frames 1-2: rays emerging, small starburst
- Frames 3-4: full starburst (peak)
- Frames 5-7: shrinking back
- Frame 8: small blob (nearly back to dot)
- Local asset: `assets/claude-sparkle-thinking-sprite.svg`

## Sprite Sheet Format

```
viewBox="0 0 100 (100 × N)"   where N = number of frames
```

- Each frame occupies a 100×100 unit square
- Frames are stacked vertically (frame 0 at top, frame N-1 at bottom)
- Single `<path d="...">` element contains ALL frames as one continuous path
- SVG renders as black (`fill="currentColor"` or no fill) — colorized at display time

## How Sprites Appear on the Page

The sprites are **NOT** in JS bundles. They are rendered inline by React components:

```html
<div class="[&>svg]:block [&>svg]:w-full [&>svg]:fill-current">
  <svg viewBox="0 0 100 900"><path d="m44.724 38.665..."></path></svg>
</div>
```

The parent container clips to show one frame at a time (overflow hidden + fixed height), and JS updates the SVG's `y` offset or uses `transform: translateY()` to cycle frames.

## Extraction Procedure

### Prerequisites
- Chrome running with `--remote-debugging-port=9222`
- Chrome must have been launched **without** `--remote-allow-origins` (WebSocket needs no-origin handshake trick)
- claude.ai open in a tab

### Step 1: Connect via CDP (Chrome DevTools Protocol)

The WebSocket rejects standard `Origin` headers. Use a **raw TCP socket** handshake without the `Origin` header:

```python
import socket, os, base64, struct

# Get WebSocket URL
tabs = json.loads(urllib.request.urlopen("http://localhost:9222/json").read())
ws_path = tabs[0]["webSocketDebuggerUrl"].split("localhost:9222")[1]

# Raw TCP — no Origin header
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("localhost", 9222))
key = base64.b64encode(os.urandom(16)).decode()
request = (
    f"GET {ws_path} HTTP/1.1\r\n"
    f"Host: localhost:9222\r\n"
    f"Upgrade: websocket\r\n"
    f"Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    f"Sec-WebSocket-Version: 13\r\n"
    f"\r\n"
)
sock.sendall(request.encode())
# ... then implement ws_send/ws_recv with masking (see full script)
```

**Why raw sockets?** Chrome's `--remote-debugging-port` rejects WebSocket upgrades from `http://localhost:9222` origin. The Python `websocket` library always sends an `Origin` header. Raw TCP lets us omit it entirely.

### Step 2: Install a Polling Observer

The thinking sprite only exists in the DOM while Claude is actively thinking. It's removed as soon as streaming starts. You need aggressive polling:

```javascript
// Inject via Runtime.evaluate
window._spriteHTML = null;
window._pollInterval = setInterval(() => {
    const sprites = document.querySelectorAll('svg[viewBox="0 0 100 900"]');
    for (const svg of sprites) {
        if (!window._spriteHTML) {
            window._spriteHTML = svg.outerHTML;
        }
    }
}, 30);  // 30ms polling — must be fast, thinking phase can be short
```

### Step 3: Trigger a Response

Send a prompt that requires extended thinking (simple prompts finish too fast):

```javascript
const editor = document.querySelector('[contenteditable="true"]');
editor.focus();
document.execCommand('selectAll', false, null);
document.execCommand('insertText', false, 'Prove the Riemann hypothesis step by step');
// Then click the Send button
```

### Step 4: Collect the Captured SVG

```javascript
clearInterval(window._pollInterval);
return window._spriteHTML;  // Full SVG outerHTML
```

### Step 5: Save and Split into Frames

```bash
# Save the SVG
echo '<svg viewBox="0 0 100 900"><path d="..."></path></svg>' > sprite.svg

# Render to PNG and split
rsvg-convert -w 100 -h 900 sprite.svg -o full.png
for i in $(seq 0 8); do
    magick full.png -crop 100x100+0+$((i*100)) +repage "frame-$i.png"
done
```

## Key Gotchas

### The thinking sprite is ephemeral
It only exists in the DOM during the thinking phase (typically 1-10 seconds). Once streaming begins, it's replaced by the working sprite or removed entirely. You MUST capture it in real-time.

### Simple prompts don't trigger visible thinking
"Say hi" completes in <1 second — the thinking sprite appears and vanishes before polling catches it. Use prompts that require reasoning: math proofs, complex analysis, etc.

### viewBox size reveals frame count
- `0 0 100 800` = 8 frames (100 × 8 = 800)
- `0 0 100 900` = 9 frames (100 × 9 = 900)
- If Anthropic adds new animations, look for new viewBox patterns (e.g., `0 0 100 1000` would be 10 frames)

### Path data is NOT in JS bundles
Searched all 76 JS chunks from `assets-proxy.anthropic.com` — zero matches for sparkle path fragments. The SVG data is likely server-rendered or injected by a React component that constructs the path dynamically from data not visible in static bundle analysis.

### Two sparkle SVGs exist simultaneously
The "stop" button at the bottom of the chat also has a sparkle SVG (`viewBox="0 0 100 100"` — single frame, not a sprite sheet). Don't confuse it with the animated sprite. Filter by viewBox height > 100.

### The blurred shadow copy
Each sparkle has a sibling with `class="absolute blur-md opacity-0"` — a blurred shadow that can be activated for glow effects. When extracting, you may see two SVGs with identical paths.

## Animation Implementation in Symmetria

Both sprites use the same frame-cycling Timer in `ClaudeSparkle.qml`:

```qml
property string mode: "working"  // "thinking" | "working"
readonly property int _frameCount: mode === "thinking" ? 9 : 8

// Two Image elements (one per sprite), toggled by `visible: mode === "..."`
// Single Timer at 101ms drives both — frameCount adapts to active mode

Timer {
    interval: 101
    onTriggered: _currentFrame = (_currentFrame + 1) % _frameCount
}
```

The `Colouriser` shader effect recolors the black SVG paths to the desired color (`#d97757` Claude brand orange).

## Searching for New Sprites

To discover if Anthropic has added new sprite sheets:

```javascript
// Run in Chrome DevTools on claude.ai during various states
document.querySelectorAll('svg').forEach(svg => {
    const vb = svg.getAttribute('viewBox') || '';
    if (vb.match(/^0 0 100 \d{3,}$/)) {
        console.log('Sprite candidate:', vb, svg.outerHTML.substring(0, 200));
    }
});
```

Look for viewBox patterns `0 0 100 N00` where N > 1 — these are likely sprite sheets.
