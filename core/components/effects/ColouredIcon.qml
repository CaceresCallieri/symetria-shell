pragma ComponentBehavior: Bound

import Symmetria
import Quickshell.Widgets
import QtQuick

IconImage {
    id: root

    required property color colour

    // Ensure minimum icon request size to prevent 2x2 pixel warnings
    // Uses actual dimensions when anchored, falls back to 16px minimum
    implicitSize: Math.max(width, height, 16)
    asynchronous: true

    layer.enabled: true
    layer.effect: Colouriser {
        sourceColor: analyser.dominantColour
        colorizationColor: root.colour
    }

    layer.onEnabledChanged: {
        if (layer.enabled && status === Image.Ready)
            analyser.requestUpdate();
    }

    onStatusChanged: {
        if (layer.enabled && status === Image.Ready)
            analyser.requestUpdate();
    }

    ImageAnalyser {
        id: analyser

        sourceItem: root
    }
}
