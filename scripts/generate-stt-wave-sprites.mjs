#!/usr/bin/env node
/**
 * Generate STT recording wave sprite sheets: 5 bars with looping ripple animation.
 *
 * Creates 3 variations of seamlessly-looping wave animations for the agentbar
 * STT recording state. Bar geometry matches the final frame of stt-morph
 * (same x positions, width, capsule rounding).
 *
 * Frame layout: 12 frames, 100x100 each, viewBox "0 0 100 1200"
 *
 * Variations:
 *   1. Traveling ripple  — wave sweeps left to right across bars
 *   2. Center pulse      — center bar leads, edges follow symmetrically
 *   3. Syncopated        — compound frequencies for organic, less predictable feel
 *
 * Output: assets/claude-sparkle-stt-wave-{1,2,3}-sprite.svg
 *
 * Usage:
 *   node scripts/generate-stt-wave-sprites.mjs             # Just generate SVGs
 *   node scripts/generate-stt-wave-sprites.mjs --preview    # Also generate preview HTML
 */

import { writeFileSync, mkdirSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ASSETS_DIR = resolve(__dirname, "..", "assets");

// ── Animation parameters ────────────────────────────────────────────
const FRAME_SIZE = 100;
const NUM_FRAMES = 12; // 12 frames × 80ms = 960ms cycle (~1Hz breathing rhythm)

// ── Bar geometry (matches stt-morph final frame positions) ──────────
const BAR_WIDTH = 12;
const BAR_RADIUS = BAR_WIDTH / 2; // Fully-rounded capsule ends

// Each bar oscillates between minH and maxH. The bell-curve shape is
// preserved: center bar has the widest range, outer bars the narrowest.
const BARS = [
    { cx: 18, minH: 15, maxH: 55 }, // Outer left  (range: 40)
    { cx: 34, minH: 18, maxH: 72 }, // Inner left  (range: 54)
    { cx: 50, minH: 22, maxH: 90 }, // Center      (range: 68)
    { cx: 66, minH: 18, maxH: 72 }, // Inner right (range: 54)
    { cx: 82, minH: 15, maxH: 55 }, // Outer right (range: 40)
];

const TWO_PI = 2 * Math.PI;

// ── Utilities ───────────────────────────────────────────────────────
function round1(v) {
    return Math.round(v * 10) / 10;
}

/**
 * Generate a capsule (pill) SVG path for a bar centered at y=50.
 * Same path structure as generate-stt-morph-sprite.mjs.
 */
function barToPath(cx, h) {
    const r = BAR_RADIUS;
    h = Math.max(h, BAR_WIDTH + 0.1); // Prevent degenerate capsule
    const top = round1(50 - h / 2);
    const bottom = round1(50 + h / 2);
    const topR = round1(top + r);
    const bottomR = round1(bottom - r);
    return `M ${cx - r} ${topR} A ${r} ${r} 0 0 1 ${cx + r} ${topR} L ${cx + r} ${bottomR} A ${r} ${r} 0 0 1 ${cx - r} ${bottomR} Z`;
}

// ── Wave functions ──────────────────────────────────────────────────
// All functions return a height in [minH, maxH] for the given bar/frame.
// They complete exactly one full cycle over NUM_FRAMES, ensuring seamless looping.

/**
 * Variation 1: Traveling Ripple
 * A single sine wave sweeps left-to-right. Each bar is phase-shifted
 * by 2π/5 from its neighbor, so one full wavelength spans all 5 bars.
 */
function travelingRipple(barIndex, frame) {
    const t = TWO_PI * frame / NUM_FRAMES;
    const phase = barIndex * (TWO_PI / 5); // 72° between adjacent bars
    const bar = BARS[barIndex];
    const wave = 0.5 + 0.5 * Math.sin(t - phase);
    return bar.minH + (bar.maxH - bar.minH) * wave;
}

/**
 * Variation 2: Center Pulse
 * Center bar leads the oscillation; inner bars follow with π/2 delay;
 * outer bars follow with π delay. Creates a symmetric "breathing" ripple.
 */
function centerPulse(barIndex, frame) {
    const t = TWO_PI * frame / NUM_FRAMES;
    const distFromCenter = Math.abs(barIndex - 2); // 2,1,0,1,2
    const phase = distFromCenter * (Math.PI / 2); // 90° per step outward
    const bar = BARS[barIndex];
    const wave = 0.5 + 0.5 * Math.sin(t - phase);
    return bar.minH + (bar.maxH - bar.minH) * wave;
}

/**
 * Variation 3: Syncopated
 * Primary wave (traveling right) + secondary harmonic (traveling left, 2× freq).
 * The interference creates a less predictable, more organic rhythm.
 * Both components complete integer cycles over NUM_FRAMES → seamless loop.
 */
function syncopated(barIndex, frame) {
    const t = TWO_PI * frame / NUM_FRAMES;
    const phase1 = barIndex * (TWO_PI / 5); // Primary: same as traveling ripple
    const phase2 = (4 - barIndex) * (Math.PI / 3); // Secondary: reversed direction
    const bar = BARS[barIndex];
    const primary = 0.65 * Math.sin(t - phase1);
    const secondary = 0.35 * Math.sin(2 * t - phase2);
    // Combined amplitude bounded by [-1, 1] since |0.65| + |0.35| = 1.0
    const wave = Math.max(0, Math.min(1, 0.5 + 0.5 * (primary + secondary)));
    return bar.minH + (bar.maxH - bar.minH) * wave;
}

const VARIATIONS = [
    { name: "stt-wave-1", label: "Traveling Ripple", fn: travelingRipple },
    { name: "stt-wave-2", label: "Center Pulse", fn: centerPulse },
    { name: "stt-wave-3", label: "Syncopated", fn: syncopated },
];

// ── SVG generation ──────────────────────────────────────────────────
function generateSprite(variation) {
    const totalHeight = FRAME_SIZE * NUM_FRAMES;
    const parts = [
        `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${FRAME_SIZE} ${totalHeight}">`,
    ];

    for (let f = 0; f < NUM_FRAMES; f++) {
        const yOff = f * FRAME_SIZE;
        for (let b = 0; b < BARS.length; b++) {
            const h = variation.fn(b, f);
            parts.push(
                `<path d="${barToPath(BARS[b].cx, h)}" transform="translate(0,${yOff})"/>`,
            );
        }
    }

    parts.push("</svg>");
    const svg = parts.join("\n");
    const outputPath = resolve(
        ASSETS_DIR,
        `claude-sparkle-${variation.name}-sprite.svg`,
    );
    writeFileSync(outputPath, svg);
    console.log(
        `  ${variation.label}: ${svg.length} bytes → ${outputPath}`,
    );
    return svg;
}

// ── Preview HTML ────────────────────────────────────────────────────
function generatePreviewHTML(svgByName) {
    const previewDir = "/tmp/stt-wave-preview";
    if (!existsSync(previewDir)) mkdirSync(previewDir, { recursive: true });

    // Convert SVG content to data URIs for self-contained HTML
    const dataUris = {};
    for (const v of VARIATIONS) {
        const b64 = Buffer.from(svgByName[v.name]).toString("base64");
        dataUris[v.name] = `data:image/svg+xml;base64,${b64}`;
    }

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>STT Wave Sprite Preview</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    background: #121212;
    color: #e0e0e0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    padding: 32px;
}
h1 { font-size: 20px; margin-bottom: 24px; color: #fff; }
h2 { font-size: 14px; color: #888; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
.section { margin-bottom: 32px; }
.row {
    display: flex;
    gap: 48px;
    align-items: flex-end;
}
.sprite-col {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
}
.sprite-clip {
    overflow: hidden;
    border: 1px solid #333;
    border-radius: 4px;
    background: #1a1a1a;
}
.sprite-clip img {
    display: block;
    image-rendering: auto;
}
.label {
    font-size: 12px;
    color: #aaa;
}
.controls {
    margin-bottom: 24px;
    display: flex;
    gap: 12px;
    align-items: center;
}
button {
    background: #333;
    color: #fff;
    border: 1px solid #555;
    border-radius: 4px;
    padding: 6px 14px;
    cursor: pointer;
    font-size: 13px;
}
button:hover { background: #444; }
button.active { background: #d97757; border-color: #d97757; }
.speed-label { font-size: 12px; color: #888; margin-left: 8px; }
/* Orange tint overlay to simulate Colouriser effect */
.tinted .sprite-clip {
    position: relative;
}
.tinted .sprite-clip::after {
    content: "";
    position: absolute;
    inset: 0;
    background: #d97757;
    mix-blend-mode: multiply;
    pointer-events: none;
}
</style>
</head>
<body>
<h1>STT Wave Sprite Preview</h1>

<div class="controls">
    <button id="playPause" class="active">Pause</button>
    <button id="stepBack">&larr; Prev</button>
    <button id="stepFwd">Next &rarr;</button>
    <button id="toggleTint">Toggle Tint</button>
    <span class="speed-label">80ms/frame &middot; 960ms cycle &middot; 12 frames</span>
</div>

<div class="section">
    <h2>Actual size (~20px) &mdash; as rendered in agentbar</h2>
    <div class="row" id="row-small"></div>
</div>

<div class="section">
    <h2>Medium (60px)</h2>
    <div class="row" id="row-medium"></div>
</div>

<div class="section">
    <h2>Large preview (120px)</h2>
    <div class="row" id="row-large"></div>
</div>

<script>
const SPRITES = ${JSON.stringify(VARIATIONS.map((v) => ({ name: v.name, label: v.label })))};
const DATA_URIS = ${JSON.stringify(dataUris)};
const NUM_FRAMES = ${NUM_FRAMES};
const INTERVAL = 80;

let frame = 0;
let playing = true;
const allImgs = [];

function createPreview(sprite, size, container) {
    const col = document.createElement("div");
    col.className = "sprite-col";

    const clip = document.createElement("div");
    clip.className = "sprite-clip";
    clip.style.width = size + "px";
    clip.style.height = size + "px";

    const img = document.createElement("img");
    img.src = DATA_URIS[sprite.name];
    img.style.width = size + "px";
    img.style.height = (size * NUM_FRAMES) + "px";
    img.dataset.size = size;

    const label = document.createElement("div");
    label.className = "label";
    label.textContent = sprite.label;

    clip.appendChild(img);
    col.appendChild(clip);
    col.appendChild(label);
    container.appendChild(col);
    allImgs.push(img);
}

SPRITES.forEach(s => {
    createPreview(s, 20, document.getElementById("row-small"));
    createPreview(s, 60, document.getElementById("row-medium"));
    createPreview(s, 120, document.getElementById("row-large"));
});

function updateFrame() {
    for (const img of allImgs) {
        const size = parseFloat(img.dataset.size);
        img.style.transform = "translateY(-" + (frame * size) + "px)";
    }
}

let timer = setInterval(() => {
    if (playing) { frame = (frame + 1) % NUM_FRAMES; updateFrame(); }
}, INTERVAL);

document.getElementById("playPause").addEventListener("click", function() {
    playing = !playing;
    this.textContent = playing ? "Pause" : "Play";
    this.classList.toggle("active", playing);
});
document.getElementById("stepBack").addEventListener("click", () => {
    playing = false;
    document.getElementById("playPause").textContent = "Play";
    document.getElementById("playPause").classList.remove("active");
    frame = (frame - 1 + NUM_FRAMES) % NUM_FRAMES;
    updateFrame();
});
document.getElementById("stepFwd").addEventListener("click", () => {
    playing = false;
    document.getElementById("playPause").textContent = "Play";
    document.getElementById("playPause").classList.remove("active");
    frame = (frame + 1) % NUM_FRAMES;
    updateFrame();
});
document.getElementById("toggleTint").addEventListener("click", () => {
    document.body.classList.toggle("tinted");
});

updateFrame();
</script>
</body>
</html>`;

    const outputPath = resolve(previewDir, "index.html");
    writeFileSync(outputPath, html);
    console.log(`\nPreview HTML: ${outputPath}`);
    console.log("Open in browser: xdg-open " + outputPath);
}

// ── Main ────────────────────────────────────────────────────────────
function main() {
    console.log(
        `Generating ${VARIATIONS.length} STT wave sprites (${NUM_FRAMES} frames × ${FRAME_SIZE}×${FRAME_SIZE}px)...\n`,
    );

    const svgByName = {};
    for (const v of VARIATIONS) {
        svgByName[v.name] = generateSprite(v);
    }

    if (process.argv.includes("--preview")) {
        generatePreviewHTML(svgByName);
    }

    console.log("\nDone!");
}

main();
