#!/usr/bin/env python3
"""
Discover all SVG sprite sheets on claude.ai via Chrome DevTools Protocol.

Prerequisites:
  1. Launch Chrome with: google-chrome-stable --remote-debugging-port=9222
     (do NOT use --remote-allow-origins)
  2. Open claude.ai and log in
  3. Run this script

The script installs a continuous DOM observer that captures every SVG element
with a multi-frame viewBox pattern (height > width, suggesting vertical sprite
stacking). It deduplicates by path data hash and reports new discoveries in
real-time.

Usage:
  python3 discover-claude-sprites.py [--duration SECONDS] [--output-dir DIR]

Then interact with claude.ai — send prompts, trigger extended thinking,
use tools, etc. The script captures sprites as they appear in the DOM.
"""

import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time
import urllib.request
from pathlib import Path


# ── WebSocket helpers (raw TCP, no Origin header) ───────────────────────

def ws_connect(host: str, port: int, path: str) -> socket.socket:
    """Open a raw WebSocket connection without sending an Origin header."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((host, port))

    key = base64.b64encode(os.urandom(16)).decode()
    handshake = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    sock.sendall(handshake.encode())

    # Read HTTP response until \r\n\r\n
    response = b""
    while b"\r\n\r\n" not in response:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("WebSocket handshake failed: connection closed")
        response += chunk

    if b"101" not in response.split(b"\r\n")[0]:
        raise ConnectionError(f"WebSocket handshake rejected:\n{response.decode(errors='replace')}")

    sock.settimeout(2)  # Non-blocking reads for polling
    return sock


def ws_send(sock: socket.socket, data: str) -> None:
    """Send a masked WebSocket text frame."""
    payload = data.encode("utf-8")
    frame = bytearray()

    # FIN + text opcode
    frame.append(0x81)

    # Length + mask bit
    length = len(payload)
    if length <= 125:
        frame.append(0x80 | length)
    elif length <= 65535:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", length))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack(">Q", length))

    # Mask key + masked payload
    mask = os.urandom(4)
    frame.extend(mask)
    frame.extend(bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    sock.sendall(frame)


def ws_recv(sock: socket.socket) -> str | None:
    """Receive a WebSocket text frame. Returns None on timeout."""
    try:
        header = sock.recv(2)
        if len(header) < 2:
            return None
    except socket.timeout:
        return None

    opcode = header[0] & 0x0F
    masked = bool(header[1] & 0x80)
    length = header[1] & 0x7F

    if length == 126:
        length = struct.unpack(">H", sock.recv(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", sock.recv(8))[0]

    mask = b""
    if masked:
        mask = sock.recv(4)

    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk

    if masked:
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))

    # Handle close frame
    if opcode == 0x08:
        raise ConnectionError("WebSocket closed by server")

    # Handle ping → send pong
    if opcode == 0x09:
        pong = bytearray([0x8A, 0x80 | len(data)])
        pong.extend(os.urandom(4))  # mask
        sock.sendall(pong)
        return None

    if opcode == 0x01:  # text
        return data.decode("utf-8", errors="replace")

    return None


# ── CDP helpers ─────────────────────────────────────────────────────────

_msg_id = 0

def cdp_send(sock: socket.socket, method: str, params: dict | None = None) -> int:
    """Send a CDP command. Returns the message ID."""
    global _msg_id
    _msg_id += 1
    msg = {"id": _msg_id, "method": method}
    if params:
        msg["params"] = params
    ws_send(sock, json.dumps(msg))
    return _msg_id


def cdp_recv_until(sock: socket.socket, msg_id: int, timeout: float = 10,
                   max_frames: int = 500) -> dict:
    """Read WebSocket frames until we get the response for msg_id.

    Drains up to max_frames of CDP event noise (console logs, exceptions, etc.)
    that arrive between our request and response.
    """
    deadline = time.time() + timeout
    frames_read = 0
    while time.time() < deadline and frames_read < max_frames:
        raw = ws_recv(sock)
        frames_read += 1
        if raw is None:
            continue
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == msg_id:
            return msg
    raise TimeoutError(f"No response for CDP message {msg_id} within {timeout}s ({frames_read} frames drained)")


def cdp_evaluate(sock: socket.socket, expression: str, timeout: float = 15) -> dict:
    """Evaluate JS in the page and return the result."""
    mid = cdp_send(sock, "Runtime.evaluate", {
        "expression": expression,
        "returnByValue": True,
        "awaitPromise": False,
    })
    return cdp_recv_until(sock, mid, timeout, max_frames=200)


# ── Sprite discovery logic ──────────────────────────────────────────────

# JS injected into the page to continuously capture SVG sprites
OBSERVER_JS = r"""
(() => {
    // Storage for discovered sprites
    if (!window._discoveredSprites) {
        window._discoveredSprites = {};
        window._spriteLog = [];
    }

    // Stop any previous observer
    if (window._spriteObserverInterval) {
        clearInterval(window._spriteObserverInterval);
    }

    function scanForSprites() {
        const svgs = document.querySelectorAll('svg[viewBox]');
        for (const svg of svgs) {
            const vb = svg.getAttribute('viewBox') || '';
            const parts = vb.split(/\s+/).map(Number);

            // We want viewBox patterns where height > width (vertical sprite stacking)
            // Standard pattern: "0 0 W H" where H > W
            if (parts.length !== 4) continue;
            const [x, y, w, h] = parts;
            if (w <= 0 || h <= 0) continue;

            // Get path data for fingerprinting
            const paths = svg.querySelectorAll('path');
            if (paths.length === 0) continue;

            const pathData = Array.from(paths).map(p => p.getAttribute('d') || '').join('|');
            // Simple hash for dedup
            const hash = pathData.substring(0, 100) + '|' + vb;

            if (window._discoveredSprites[hash]) continue;

            // Classify
            const frameCount = h > w ? Math.round(h / w) : 1;
            const isSpriteSheet = frameCount > 1;

            // Get parent context for identification
            const parent = svg.closest('[class]');
            const parentClasses = parent ? parent.className : '(none)';

            // Check for blur sibling (shadow copy)
            const isBlurCopy = parent && (
                parent.className.includes('blur') ||
                parent.className.includes('opacity-0')
            );

            const entry = {
                viewBox: vb,
                width: w,
                height: h,
                frameCount: frameCount,
                isSpriteSheet: isSpriteSheet,
                isBlurCopy: isBlurCopy,
                pathCount: paths.length,
                pathDataLength: pathData.length,
                pathSnippet: pathData.substring(0, 200),
                parentClasses: typeof parentClasses === 'string' ? parentClasses.substring(0, 300) : String(parentClasses).substring(0, 300),
                outerHTML: svg.outerHTML,
                timestamp: Date.now(),
            };

            window._discoveredSprites[hash] = entry;
            window._spriteLog.push({
                event: 'new_sprite',
                hash: hash.substring(0, 50),
                viewBox: vb,
                frameCount: frameCount,
                isSpriteSheet: isSpriteSheet,
                isBlurCopy: isBlurCopy,
                timestamp: Date.now(),
            });
        }
    }

    // Aggressive polling — sprites can be very ephemeral
    window._spriteObserverInterval = setInterval(scanForSprites, 25);

    // Also scan immediately
    scanForSprites();

    return 'Observer installed — polling every 25ms';
})()
"""

COLLECT_JS = r"""
(() => {
    const sprites = window._discoveredSprites || {};
    const log = window._spriteLog || [];

    // Clear the log after reading (keep sprites for dedup)
    window._spriteLog = [];

    return JSON.stringify({
        totalDiscovered: Object.keys(sprites).length,
        newEvents: log,
        sprites: sprites,
    });
})()
"""

KNOWN_VIEWBOXES = {
    "0 0 100 800": "Working/streaming (8 frames) — ALREADY EXTRACTED",
    "0 0 100 900": "Thinking/breathing (9 frames) — ALREADY EXTRACTED",
    "0 0 100 100": "Static sparkle (stop button, 1 frame) — known, not a sprite sheet",
}


def classify_sprite(entry: dict) -> str:
    """Classify a discovered sprite."""
    vb = entry["viewBox"]
    if vb in KNOWN_VIEWBOXES:
        return KNOWN_VIEWBOXES[vb]

    if entry["isBlurCopy"]:
        return "Blur/shadow copy (duplicate)"

    if entry["isSpriteSheet"]:
        return f"*** NEW SPRITE SHEET *** — {entry['frameCount']} frames!"

    return "Static SVG (single frame)"


def save_sprite(entry: dict, output_dir: Path, index: int) -> Path:
    """Save a sprite's SVG to disk."""
    vb_slug = entry["viewBox"].replace(" ", "_")
    filename = f"sprite_{index:02d}_vb_{vb_slug}.svg"
    path = output_dir / filename
    path.write_text(entry["outerHTML"])
    return path


def main():
    parser = argparse.ArgumentParser(description="Discover Claude.ai SVG sprite sheets via CDP")
    parser.add_argument("--duration", type=int, default=120,
                        help="How long to monitor (seconds). Default: 120")
    parser.add_argument("--output-dir", type=str, default="/tmp/claude-sprites",
                        help="Directory to save discovered sprites. Default: /tmp/claude-sprites")
    parser.add_argument("--port", type=int, default=9222,
                        help="Chrome debugging port. Default: 9222")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # ── Step 1: Find the claude.ai tab ──────────────────────────────────
    print(f"[*] Connecting to Chrome on port {args.port}...")
    try:
        tabs_raw = urllib.request.urlopen(f"http://localhost:{args.port}/json").read()
        tabs = json.loads(tabs_raw)
    except Exception as e:
        print(f"[!] Cannot connect to Chrome. Make sure it's running with --remote-debugging-port={args.port}")
        print(f"    Error: {e}")
        sys.exit(1)

    # Find a claude.ai tab
    claude_tab = None
    for tab in tabs:
        url = tab.get("url", "")
        if "claude.ai" in url and tab.get("webSocketDebuggerUrl"):
            claude_tab = tab
            break

    if not claude_tab:
        print("[!] No claude.ai tab found. Open claude.ai in Chrome first.")
        print(f"    Found {len(tabs)} tab(s):")
        for t in tabs:
            print(f"      - {t.get('url', '?')}")
        sys.exit(1)

    ws_url = claude_tab["webSocketDebuggerUrl"]
    ws_path = "/" + ws_url.split("/", 3)[-1]
    print(f"[+] Found claude.ai tab: {claude_tab['url'][:80]}")
    print(f"    WebSocket: {ws_path[:60]}...")

    # ── Step 2: Connect via raw WebSocket ───────────────────────────────
    print("[*] Connecting via raw WebSocket (no Origin header)...")
    sock = ws_connect("localhost", args.port, ws_path)
    print("[+] WebSocket connected!")

    # ── Step 3: Install the observer ────────────────────────────────────
    # NOTE: We skip Runtime.enable intentionally — it floods the WebSocket
    # with consoleAPICalled/exceptionThrown events from the page, drowning
    # out our evaluation responses. Runtime.evaluate works without it.
    print("[*] Installing SVG sprite observer (25ms polling)...")
    result = cdp_evaluate(sock, OBSERVER_JS)
    if "error" in result.get("result", {}):
        print(f"[!] Observer injection failed: {result}")
        sys.exit(1)
    print(f"[+] {result.get('result', {}).get('result', {}).get('value', 'Observer installed')}")

    # ── Step 5: Monitor loop ────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  MONITORING claude.ai for {args.duration}s")
    print(f"  Interact with Claude to trigger different animation states:")
    print(f"    - Send a simple prompt (streaming sparkle)")
    print(f"    - Send a hard prompt (extended thinking sparkle)")
    print(f"    - Use tools/computer use if available")
    print(f"    - Upload a file")
    print(f"    - Try different Claude models")
    print(f"  Output: {output_dir}")
    print(f"{'='*60}\n")

    start_time = time.time()
    last_total = 0
    saved_sprites = set()

    try:
        while time.time() - start_time < args.duration:
            elapsed = int(time.time() - start_time)

            # Poll for new discoveries
            try:
                result = cdp_evaluate(sock, COLLECT_JS, timeout=5)
            except (TimeoutError, ConnectionError) as e:
                print(f"  [{elapsed:3d}s] Warning: {e}")
                continue

            value = result.get("result", {}).get("result", {}).get("value")
            if not value:
                time.sleep(1)
                continue

            try:
                data = json.loads(value)
            except json.JSONDecodeError:
                time.sleep(1)
                continue

            total = data["totalDiscovered"]

            # Print new event notifications
            for event in data["newEvents"]:
                tag = "NEW!" if event["isSpriteSheet"] and not event["isBlurCopy"] else "    "
                blur = " (blur copy)" if event["isBlurCopy"] else ""
                frames = f"{event['frameCount']} frames" if event["frameCount"] > 1 else "static"
                print(f"  [{elapsed:3d}s] {tag} viewBox={event['viewBox']}  ({frames}){blur}")

            # Save any new sprites we haven't saved yet
            for hash_key, entry in data["sprites"].items():
                short_hash = hashlib.md5(hash_key.encode()).hexdigest()[:8]
                if short_hash not in saved_sprites:
                    saved_sprites.add(short_hash)
                    idx = len(saved_sprites)
                    filepath = save_sprite(entry, output_dir, idx)
                    classification = classify_sprite(entry)
                    if "NEW SPRITE SHEET" in classification:
                        print(f"  [{elapsed:3d}s] *** SAVED: {filepath.name} — {classification}")
                    # Save metadata
                    meta_path = filepath.with_suffix(".json")
                    meta = {k: v for k, v in entry.items() if k != "outerHTML"}
                    meta["classification"] = classification
                    meta_path.write_text(json.dumps(meta, indent=2))

            if total != last_total:
                last_total = total

            time.sleep(2)  # Poll every 2 seconds

    except KeyboardInterrupt:
        print("\n[*] Interrupted by user")
    except ConnectionError as e:
        print(f"\n[!] Connection lost: {e}")

    # ── Step 6: Final report ────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  DISCOVERY REPORT")
    print(f"{'='*60}")

    # Collect final state
    try:
        result = cdp_evaluate(sock, COLLECT_JS, timeout=5)
        value = result.get("result", {}).get("result", {}).get("value")
        if value:
            data = json.loads(value)
            sprites = data["sprites"]

            # Group by viewBox
            by_viewbox: dict[str, list] = {}
            for entry in sprites.values():
                vb = entry["viewBox"]
                by_viewbox.setdefault(vb, []).append(entry)

            for vb, entries in sorted(by_viewbox.items()):
                primary = [e for e in entries if not e["isBlurCopy"]]
                blur_count = len(entries) - len(primary)
                entry = primary[0] if primary else entries[0]

                classification = classify_sprite(entry)
                print(f"\n  viewBox: {vb}")
                print(f"    Frames: {entry['frameCount']}")
                print(f"    Path length: {entry['pathDataLength']} chars")
                print(f"    Blur copies: {blur_count}")
                print(f"    Classification: {classification}")

            # Highlight NEW discoveries
            new_sheets = [
                e for entries in by_viewbox.values()
                for e in entries
                if e["isSpriteSheet"] and not e["isBlurCopy"]
                and e["viewBox"] not in KNOWN_VIEWBOXES
            ]

            if new_sheets:
                print(f"\n  *** {len(new_sheets)} NEW SPRITE SHEET(S) FOUND! ***")
                for entry in new_sheets:
                    print(f"    - viewBox={entry['viewBox']} ({entry['frameCount']} frames)")
                    print(f"      Path snippet: {entry['pathSnippet'][:100]}...")
            else:
                print(f"\n  No new sprite sheets found (only known animations detected).")
                print(f"  Try more interactions: extended thinking, tool use, file uploads.")

    except Exception as e:
        print(f"  Could not collect final report: {e}")

    print(f"\n  All sprites saved to: {output_dir}")
    print(f"{'='*60}")

    # Cleanup
    try:
        # Stop the observer
        cdp_evaluate(sock, "clearInterval(window._spriteObserverInterval)", timeout=3)
    except Exception:
        pass

    try:
        sock.close()
    except Exception:
        pass


if __name__ == "__main__":
    main()
