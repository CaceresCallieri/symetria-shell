pragma ComponentBehavior: Bound

import qs.components.effects
import qs.config
import QtQuick

// Frozen beams-metal sheet as the FOCUS-MODE BACKDROP.
//
// While focus mode fades the image wallpapers out, this fades in instead of
// the bare surface colour. Normal (non-focus) wallpapers are untouched — the
// image stack sits ABOVE this item and always wins visually.
//
// Reuses the lock screen's shader and its calibrated material, with the
// wallpaper's own geometry: ONE beam wide enough to cover the whole screen,
// which reads as a single draped metal sheet. The diagonal seam across the
// frame is the band boundary at q.x = 0 — kept deliberately, it is part of
// the picked composition (and is why the sheet cannot be done by parameters
// alone without it: any beamWidth that covers the screen puts a boundary on
// screen; see the rejected params-only attempts in the wallpaper prototype).
//
// Frozen on purpose: `animating: false` stops the time animation, so the GPU
// renders one frame and idles — zero ongoing cost. `time` selects WHICH
// moment is frozen (the composition seed); it is configurable so the
// composition can change without a code edit.
BeamsBackground {
    id: root

    anchors.fill: parent

    animating: false
    time: Config.background.focusBackdrop.time

    // Material shared with the lock screen so both stay one metal family;
    // the wallpaper overrides only what defines ITS look. frontGlow is 0
    // because no reveal ever plays (reveal stays at its default of 1: the
    // frame is fully opaque). The base map is LockConfig.Beams.material —
    // the canonical mapping; do not spell the keys out here again.
    cfg: Object.assign({}, Config.lock.beams.material, {
        noiseScale: 0.07,
        beamWidth: 40,
        frontGlow: 0
    })
}
