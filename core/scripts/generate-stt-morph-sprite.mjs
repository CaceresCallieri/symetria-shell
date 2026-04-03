#!/usr/bin/env node
/**
 * Generate the STT morph sprite sheet: Claude sparkle → 5 rounded bars.
 *
 * Uses flubber.separate() to decompose the sparkle into 5 pieces, each
 * morphing independently toward one target bar shape. This creates an
 * organic "fracture into bars" effect rather than a blobby direct morph.
 *
 * Frame layout (12 frames, 100×100 each, viewBox 0 0 100 1200):
 *   Frame 0:     Original sparkle path (single path, smooth — avoids seam artifacts)
 *   Frames 1–10: Morph via flubber.separate() at eased t values
 *   Frame 11:    Final rounded bars (hold frame)
 *
 * Output: assets/claude-sparkle-stt-morph-sprite.svg
 *
 * Usage: node scripts/generate-stt-morph-sprite.mjs [--preview]
 *   --preview  Also outputs individual frame SVGs to /tmp/stt-morph-frames/
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import flubber from "flubber";
const { separate } = flubber;

const __dirname = dirname(fileURLToPath(import.meta.url));
const ASSETS_DIR = resolve(__dirname, "..", "assets");
const WORKING_SPRITE = resolve(ASSETS_DIR, "claude-sparkle-sprite.svg");
const OUTPUT_SPRITE = resolve(
    ASSETS_DIR,
    "claude-sparkle-stt-morph-sprite.svg",
);

// ── Animation parameters ─────────────────────────────────────────────
const FRAME_SIZE = 100;
const NUM_MORPH_FRAMES = 10; // Frames 1–10: eased morph
const NUM_HOLD_START = 1; // Frame 0: sparkle hold
const NUM_HOLD_END = 1; // Frame 11: bars hold
const NUM_FRAMES = NUM_HOLD_START + NUM_MORPH_FRAMES + NUM_HOLD_END; // 12

// ── Bar definitions ──────────────────────────────────────────────────
// 5 pill-shaped bars, centered at y=50 in the 100×100 viewBox.
// Total span: bars from x=13 to x=87 (74px), symmetric.
const BAR_WIDTH = 12;
const BAR_RADIUS = BAR_WIDTH / 2; // Fully rounded capsule ends
const BARS = [
    { cx: 18, h: 35 }, // Short outer bar
    { cx: 34, h: 55 }, // Medium bar
    { cx: 50, h: 80 }, // Tall center bar
    { cx: 66, h: 55 }, // Medium bar (symmetric)
    { cx: 82, h: 35 }, // Short outer bar (symmetric)
];

// ── Easing ───────────────────────────────────────────────────────────
function easeInOutCubic(t) {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

// ── Bar path generation ──────────────────────────────────────────────
/**
 * Generate a capsule (pill) SVG path for a bar.
 * Uses arc commands for the rounded ends.
 */
function barToPath({ cx, h }) {
    const r = BAR_RADIUS;
    const top = 50 - h / 2;
    const bottom = 50 + h / 2;

    // Capsule outline: top-left → arc across top → down right side →
    //                  arc across bottom → up left side → close
    return [
        `M ${cx - r} ${top + r}`,
        `A ${r} ${r} 0 0 1 ${cx + r} ${top + r}`,
        `L ${cx + r} ${bottom - r}`,
        `A ${r} ${r} 0 0 1 ${cx - r} ${bottom - r}`,
        `Z`,
    ].join(" ");
}

// ── Sparkle path extraction ──────────────────────────────────────────
function extractSparklePath(svgContent) {
    const match = svgContent.match(/d="([^"]+)"/);
    if (!match) throw new Error("No path d attribute found in working sprite");
    const fullPath = match[1];

    // First closed subpath = frame 0 of the working sprite
    for (let i = 0; i < fullPath.length; i++) {
        if (fullPath[i] === "z" || fullPath[i] === "Z") {
            return fullPath.slice(0, i + 1);
        }
    }
    throw new Error("No closepath (z/Z) found in working sprite");
}

// ── Sprite generation ────────────────────────────────────────────────
function generateSprite() {
    const svgContent = readFileSync(WORKING_SPRITE, "utf-8");
    const sparklePath = extractSparklePath(svgContent);
    console.log(`Sparkle path: ${sparklePath.length} chars`);

    const barPaths = BARS.map(barToPath);
    console.log(
        `Bar paths: ${barPaths.length} bars (widths: ${BAR_WIDTH}px, heights: ${BARS.map((b) => b.h).join(", ")})`,
    );

    // Create morph interpolators: 1 sparkle → 5 bars
    // Returns an array of 5 functions, one per target bar.
    // Each function takes t (0→1) and returns a path string.
    // maxSegmentLength controls polygon resolution (lower = smoother but more data)
    const interpolators = separate(sparklePath, barPaths, {
        maxSegmentLength: 2,
    });
    console.log(`Created ${interpolators.length} interpolators`);

    const totalHeight = FRAME_SIZE * NUM_FRAMES;
    const parts = [];
    parts.push(
        `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${FRAME_SIZE} ${totalHeight}">`,
    );

    const previewFrames = [];

    for (let i = 0; i < NUM_FRAMES; i++) {
        const yOff = i * FRAME_SIZE;

        if (i === 0) {
            // Hold frame: original sparkle as a single smooth path
            parts.push(`<path d="${sparklePath}" transform="translate(0,${yOff})"/>`);
            previewFrames.push([sparklePath]);
        } else if (i === NUM_FRAMES - 1) {
            // Hold frame: final bars (interpolators at t=1 for exact match)
            const paths = interpolators.map((fn) => fn(1.0));
            for (const p of paths) {
                parts.push(`<path d="${p}" transform="translate(0,${yOff})"/>`);
            }
            previewFrames.push(paths);
        } else {
            // Morph frames: eased t from 0 → 1 across NUM_MORPH_FRAMES steps
            const morphIndex = i - NUM_HOLD_START; // 0 to 9
            const t = morphIndex / (NUM_MORPH_FRAMES - 1); // 0/9 to 9/9
            const eased = easeInOutCubic(t);

            const paths = interpolators.map((fn) => fn(eased));
            for (const p of paths) {
                parts.push(`<path d="${p}" transform="translate(0,${yOff})"/>`);
            }
            previewFrames.push(paths);
            console.log(
                `  Frame ${i}: t=${t.toFixed(3)} → eased=${eased.toFixed(3)}`,
            );
        }
    }

    parts.push("</svg>");
    const svg = parts.join("\n");
    writeFileSync(OUTPUT_SPRITE, svg);
    console.log(
        `\nGenerated ${OUTPUT_SPRITE}\n  ${svg.length} bytes, ${NUM_FRAMES} frames`,
    );

    // Optional: output individual frame previews
    if (process.argv.includes("--preview")) {
        const previewDir = "/tmp/stt-morph-frames";
        if (!existsSync(previewDir)) mkdirSync(previewDir, { recursive: true });

        for (let i = 0; i < previewFrames.length; i++) {
            const paths = previewFrames[i];
            const frameSvg = [
                `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${FRAME_SIZE} ${FRAME_SIZE}" width="200" height="200">`,
                `<rect width="100" height="100" fill="#1a1a1a"/>`,
                ...paths.map((p) => `<path d="${p}" fill="white"/>`),
                "</svg>",
            ].join("\n");
            writeFileSync(`${previewDir}/frame-${String(i).padStart(2, "0")}.svg`, frameSvg);
        }
        console.log(`\nFrame previews saved to ${previewDir}/`);
    }
}

generateSprite();
