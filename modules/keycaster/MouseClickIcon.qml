pragma ComponentBehavior: Bound

import QtQuick

/// Mouse click icon drawn via Canvas with per-button opacity highlighting.
///
/// Draws a minimalist mouse silhouette where the active button region is fully
/// opaque and inactive regions are at reduced opacity. Rendered CPU-side via
/// QPainter (Canvas) because both QML Shape and Image with layer.enabled (GPU
/// FBO pipeline) fail to render at small sizes (~14×22px) in Quickshell's
/// Wayland layer-shell context.
///
/// After editing this file, clear QML cache before restarting:
///   rm -rf ~/.cache/quickshell/qmlcache
Item {
    id: root

    /// Which button is active: "left", "right", or "middle"
    required property string activeButton

    /// Target color for the icon (typically the chip's text color)
    property color baseColor: "white"

    // ── Drawing constants (proportions relative to icon size) ──
    readonly property real activeOpacity: 1.0
    readonly property real inactiveOpacity: 0.35
    readonly property real cornerRadiusRatio: 0.28
    readonly property real buttonHeightRatio: 0.36
    readonly property real wheelRadiusXRatio: 0.10
    readonly property real wheelRadiusYRatio: 0.14
    readonly property real wheelYPositionRatio: 0.6
    readonly property int dividerGapPx: 1

    implicitWidth: 16
    implicitHeight: 24

    Canvas {
        id: canvas

        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        // Repaint when any input changes
        onPaint: root.drawMouse(getContext("2d"), width, height)

        Connections {
            function onActiveButtonChanged(): void {
                canvas.requestPaint();
            }
            function onBaseColorChanged(): void {
                canvas.requestPaint();
            }

            target: root
        }
    }

    function drawMouse(ctx: var, w: real, h: real): void {
        ctx.clearRect(0, 0, w, h);

        const c = baseColor;
        const hi = activeOpacity;
        const lo = inactiveOpacity;
        const gap = dividerGapPx;

        const r = w * cornerRadiusRatio;
        const midX = w / 2;
        const btnH = h * buttonHeightRatio;
        const bodyY = btnH + gap;

        const wheelRX = w * wheelRadiusXRatio;
        const wheelRY = h * wheelRadiusYRatio;
        const wheelCX = midX;
        const wheelCY = btnH * wheelYPositionRatio;

        // ── Left button (top-left with rounded TL corner) ──
        ctx.beginPath();
        ctx.moveTo(r, 0);
        ctx.lineTo(midX - gap / 2, 0);
        ctx.lineTo(midX - gap / 2, btnH);
        ctx.lineTo(0, btnH);
        ctx.lineTo(0, r);
        ctx.arcTo(0, 0, r, 0, r);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, activeButton === "left" ? hi : lo);
        ctx.fill();

        // ── Right button (top-right with rounded TR corner) ──
        ctx.beginPath();
        ctx.moveTo(midX + gap / 2, 0);
        ctx.lineTo(w - r, 0);
        ctx.arcTo(w, 0, w, r, r);
        ctx.lineTo(w, btnH);
        ctx.lineTo(midX + gap / 2, btnH);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, activeButton === "right" ? hi : lo);
        ctx.fill();

        // ── Body (bottom with rounded BL+BR corners) ──
        ctx.beginPath();
        ctx.moveTo(0, bodyY);
        ctx.lineTo(w, bodyY);
        ctx.lineTo(w, h - r);
        ctx.arcTo(w, h, w - r, h, r);
        ctx.lineTo(r, h);
        ctx.arcTo(0, h, 0, h - r, r);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, lo);
        ctx.fill();

        // ── Scroll wheel (small ellipse via scaled arc) ──
        ctx.save();
        ctx.translate(wheelCX, wheelCY);
        ctx.scale(wheelRX, wheelRY);
        ctx.beginPath();
        ctx.arc(0, 0, 1, 0, 2 * Math.PI);
        ctx.restore();
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, activeButton === "middle" ? hi : lo);
        ctx.fill();
    }
}
