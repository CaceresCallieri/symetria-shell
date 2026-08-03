import ".."
import qs.services
import qs.config
import QtQuick

/// Matte/glass pill button using Colours.pillStyle() intensity system.
/// Supports icon-only (omit text) and icon+text modes.
/// Call triggerPress() for programmatic press feedback (e.g. keybind-triggered).
///
/// NOT MIGRATED: this used to say the selected state matched ActiveIndicator.
/// It no longer does — ActiveIndicator moved to Colours.engagedPillStyle() plus
/// the Theme.engaged finish, while `selectedBackground` below still hand-blends
/// the accent over a matte base. That makes this a remaining dialect of
/// "active", of the same kind the engaged-state work consolidated elsewhere.
/// Left alone on purpose rather than migrated blind: this button is used across
/// several panels whose look was not part of that change and was not visually
/// checked. Migrating means replacing the blend with
/// `Colours.engagedPillStyle(pillColor, Colours.glass.strong, Colours.polish.standard)`
/// and deleting the helper — a small change, but one that needs eyes on it.
Item {
    id: root

    required property string icon
    property string text: ""

    // Selection (for radio-style use like delivery mode pills)
    property bool selectable: false
    property bool selected: false

    // Colors
    property color pillColor: Colours.palette.m3primary
    property color iconColor: Colours.palette.m3onSurfaceVariant
    property color selectedIconColor: Colours.palette.m3onSurface

    // Interaction
    signal clicked()

    function triggerPress(): void {
        pressAnim.restart();
    }

    // --- Internal state ---

    readonly property bool effectiveSelected: selectable && selected
    readonly property bool hasText: root.text !== ""
    readonly property real pressSqueezeTarget: root.hasText ? 0.90 : 0.85
    readonly property real selectedAlpha: 0.30
    readonly property real selectedHoverAlpha: 0.45

    // Unselected: standard matte pill (subtle → medium on hover)
    // Selected: pillColor at visible alpha over matte base, so it actually reads as colored
    readonly property var baseStyle: Colours.pillStyle( // intentional var: heterogeneous JS { background, border }
        Colours.palette.m3surfaceContainerHigh,
        stateLayer.containsMouse ? Colours.glass.medium : Colours.glass.subtle
    )

    readonly property color selectedBackground: {
        const base = baseStyle.background;
        const accent = pillColor;
        const alpha = stateLayer.containsMouse ? root.selectedHoverAlpha : root.selectedAlpha;
        // Blend accent over matte base: result = accent * alpha + base * (1 - alpha)
        return Qt.rgba(
            accent.r * alpha + base.r * (1 - alpha),
            accent.g * alpha + base.g * (1 - alpha),
            accent.b * alpha + base.b * (1 - alpha),
            1.0
        );
    }

    readonly property var currentStyle: { // intentional var: heterogeneous JS { background, border }
        if (effectiveSelected)
            return {
                background: selectedBackground,
                border: Qt.alpha(pillColor, stateLayer.containsMouse ? 0.35 : 0.25)
            };
        return baseStyle;
    }

    readonly property color currentIconColor: effectiveSelected ? selectedIconColor : iconColor

    // --- Sizing ---

    implicitWidth: contentRow.implicitWidth + Appearance.padding.normal * 2
    implicitHeight: contentRow.implicitHeight + Appearance.padding.smaller * 2

    // --- Press squeeze animation ---

    SequentialAnimation {
        id: pressAnim

        NumberAnimation {
            target: root
            property: "scale"
            to: root.pressSqueezeTarget
            duration: 80
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "scale"
            to: 1.0
            duration: 150
            easing.type: Easing.OutBack
        }
    }

    // --- Background pill ---

    StyledRect {
        id: backgroundRect

        anchors.fill: parent
        radius: Appearance.rounding.full
        color: root.currentStyle.background
        border.width: 1
        border.color: root.currentStyle.border

        Behavior on border.color {
            CAnim {}
        }
    }

    // --- Hover/press ripple ---

    StateLayer {
        id: stateLayer

        radius: Appearance.rounding.full
        color: root.currentIconColor

        function onClicked(): void {
            root.clicked();
        }
    }

    // --- Content ---

    Row {
        id: contentRow

        anchors.centerIn: parent
        spacing: root.hasText ? Appearance.spacing.smaller : 0

        MaterialIcon {
            text: root.icon
            color: root.currentIconColor
            font.pointSize: root.hasText ? Appearance.font.size.small : Appearance.font.size.normal
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                CAnim {}
            }
        }

        StyledText {
            visible: root.hasText
            text: root.text
            color: root.currentIconColor
            font.pointSize: Appearance.font.size.small
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                CAnim {}
            }
        }
    }
}
