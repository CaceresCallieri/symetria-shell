pragma ComponentBehavior: Bound

import Quickshell
import qs.components.effects
import qs.config
import QtQuick

/// Claude sparkle: 8-frame hand-drawn starburst sprite sheet, 810ms cycle.
/// Original asset from claude.ai (Anthropic) — used with attribution.
Item {
    id: root

    required property color color
    property bool running: true

    implicitWidth: _size
    implicitHeight: _size

    // Match MaterialIcon sizing at Appearance.font.size.small
    readonly property real _size: Appearance.font.size.small * 1.4

    clip: true

    property int _currentFrame: 0

    Image {
        id: sprite

        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/claude-sparkle-sprite.svg`)
        sourceSize.width: root._size
        sourceSize.height: root._size * 8
        width: root._size
        height: root._size * 8
        y: -root._currentFrame * root._size

        // Colorize: SVG renders as black (currentColor default), remap to desired color.
        // layer.enabled is on the Image (15×120px FBO), NOT the clipped container (15×15px),
        // to avoid known small-size FBO rendering failures in Quickshell layer-shell.
        layer.enabled: true
        layer.effect: Colouriser {
            sourceColor: "black"
            colorizationColor: root.color
        }
    }

    Timer {
        running: root.running && root.visible
        interval: 101 // 810ms / 8 frames
        repeat: true
        onTriggered: root._currentFrame = (root._currentFrame + 1) % 8
    }

    onRunningChanged: if (!running) _currentFrame = 0
}
