pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual key chip for Keycaster display.
///
/// Displays a single key or key combination with glassmorphism styling.
/// Newest key is highlighted (m3primary, strong glass), older keys fade out.
/// For mouse button events, renders a graphical MouseClickIcon instead of text.
Item {
    id: root

    required property string keyText
    required property bool isNewest
    property int keyTimestamp: 0

    /// Mouse button identifier: "" for keyboard, "left"/"right"/"middle" for mouse clicks
    property string mouseButton: ""

    /// Whether this chip represents a mouse click event
    readonly property bool isMouseClick: mouseButton !== ""

    /// The text color for this chip's state (used by both text and mouse icon)
    readonly property color chipTextColor: isNewest ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

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
        implicitWidth: chipContent.implicitWidth + Appearance.padding.large * 2
        implicitHeight: chipContent.implicitHeight + Appearance.padding.normal * 2

        radius: 8  // Subtle rounding like a physical keycap
        color: glassStyle.background
        border.color: glassStyle.border
        border.width: 1

        // Content: either text label or mouse icon (with optional modifier prefix)
        Row {
            id: chipContent

            anchors.centerIn: parent
            spacing: root.isMouseClick && root.keyText !== "" ? 2 : 0

            // Modifier prefix text (e.g. "⌘+" shown before mouse icon)
            StyledText {
                id: modifierLabel

                visible: root.isMouseClick && root.keyText !== ""
                // Row manages horizontal positioning; vertical centering inherited

                text: root.keyText
                font.pointSize: Appearance.font.size.normal
                font.family: Appearance.font.family.mono
                font.weight: root.isNewest ? Font.DemiBold : Font.Normal
                color: root.chipTextColor
            }

            // Mouse click icon
            MouseClickIcon {
                id: mouseIcon

                visible: root.isMouseClick
                // Row manages horizontal positioning; vertical centering inherited

                activeButton: root.mouseButton
                baseColor: root.chipTextColor

                // Scale to match text height
                width: 14
                height: 22
            }

            // Keyboard key text label
            StyledText {
                id: keyLabel

                visible: !root.isMouseClick
                // Row manages horizontal positioning; vertical centering inherited

                text: root.keyText
                font.pointSize: Appearance.font.size.normal
                font.family: Appearance.font.family.mono
                font.weight: root.isNewest ? Font.DemiBold : Font.Normal
                color: root.chipTextColor
            }
        }
    }
}
