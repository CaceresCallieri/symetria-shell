pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual key chip for Keycaster display.
///
/// Displays a single key or key combination with glassmorphism styling.
/// Newest key is highlighted (m3primary, strong glass), older keys fade out.
Item {
    id: root

    required property string keyText
    required property bool isNewest
    property int keyTimestamp: 0

    // Fade animation constants
    readonly property real minOpacity: 0.4      // Minimum opacity for old keys
    readonly property real opacityRange: 0.6    // Range from 1.0 to minOpacity (1.0 - 0.4)

    // Fade out older keys based on age
    readonly property real targetOpacity: {
        if (isNewest)
            return 1.0;

        // Calculate age-based opacity
        const age = Date.now() - keyTimestamp;
        const fadeDelay = Config.keycaster?.fadeoutDelay ?? 2000;
        const fadeDuration = Config.keycaster?.fadeoutDuration ?? 500;

        if (age < fadeDelay)
            return 1.0;
        if (age >= fadeDelay + fadeDuration)
            return minOpacity;

        // Linear interpolation during fade
        const fadeProgress = (age - fadeDelay) / fadeDuration;
        return 1.0 - (fadeProgress * opacityRange);
    }

    // Timer to update opacity periodically for age-based fading
    Timer {
        running: !root.isNewest && root.keyTimestamp > 0
        interval: 50
        repeat: true
        onTriggered: root.targetOpacityChanged()
    }

    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight

    opacity: targetOpacity

    Behavior on opacity {
        Anim {
            duration: 100
        }
    }

    StyledRect {
        id: chip

        readonly property var glassStyle: root.isNewest
            ? Colours.glassmorphism(Colours.palette.m3primary, Colours.glass.strong)
            : Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

        // Keyboard key-like proportions: more padding, subtle rounding
        implicitWidth: keyLabel.implicitWidth + Appearance.padding.large * 2
        implicitHeight: keyLabel.implicitHeight + Appearance.padding.normal * 2

        radius: 8  // Subtle rounding like a physical keycap
        color: glassStyle.background
        border.color: glassStyle.border
        border.width: 1

        StyledText {
            id: keyLabel

            anchors.centerIn: parent

            text: root.keyText
            font.pointSize: Appearance.font.size.normal
            font.family: Appearance.font.family.mono
            font.weight: root.isNewest ? Font.DemiBold : Font.Normal
            color: root.isNewest ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
        }
    }
}
