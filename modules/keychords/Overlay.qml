pragma ComponentBehavior: Bound

import qs.components
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Centered floating dialog for KeyChords which-key display.
///
/// Shows available chord keys for the active group. All keyboard
/// input is captured — matched keys execute commands, Escape dismisses,
/// unmatched keys are silently consumed. Click outside dismisses via
/// HyprlandFocusGrab (in Drawers.qml) or the transparent catch area.
///
/// Lives as a direct child of StyledWindow in Drawers.qml (not inside
/// Panels) to avoid Region mask issues with click-through.
Item {
    id: root

    required property PersistentProperties visibilities

    readonly property bool shouldShow: visibilities.keychords && Config.keychords.enabled && KeyChordsService.active

    visible: dialogScale > 0

    // Animated properties driven by shouldShow state
    property real dialogScale: shouldShow ? 1.0 : 0.01
    property real dialogOpacity: shouldShow ? 1.0 : 0.0

    Behavior on dialogScale {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutBack
            easing.overshoot: 1.5
        }
    }

    Behavior on dialogOpacity {
        Anim {}
    }

    FocusManager {
        active: root.shouldShow
        target: dialog
    }

    // Transparent click catcher — dismiss when clicking outside the dialog
    MouseArea {
        anchors.fill: parent
        onClicked: KeyChordsService.dismiss()
    }

    // Centered dialog container
    Item {
        id: dialogWrapper

        anchors.centerIn: parent
        width: dialog.implicitWidth
        height: dialog.implicitHeight

        scale: root.dialogScale
        opacity: root.dialogOpacity

        StyledRect {
            id: dialog

            implicitWidth: dialogContent.implicitWidth + Appearance.padding.large * 2
            implicitHeight: dialogContent.implicitHeight + Appearance.padding.large * 2

            // Match panel background opacity: generalBackgroundAlpha × transparency.base
            // The unified Backgrounds system gets both reductions via nested layers,
            // but this overlay lives outside that container, so we compute it directly.
            readonly property real effectiveAlpha: Colours.generalBackgroundAlpha * (Colours.transparency.enabled ? Colours.transparency.base : 1)

            radius: Appearance.rounding.normal
            color: Qt.alpha(Colours.generalBackgroundOpaque, effectiveAlpha)

            focus: true

            Keys.onPressed: event => {
                event.accepted = true;
                if (event.text && event.text.length > 0)
                    KeyChordsService.handleKey(event.text);
            }

            Keys.onEscapePressed: event => {
                event.accepted = true;
                KeyChordsService.dismiss();
            }

            ColumnLayout {
                id: dialogContent

                anchors.centerIn: parent
                spacing: Appearance.spacing.large

                // Group title
                StyledText {
                    Layout.alignment: Qt.AlignHCenter

                    text: KeyChordsService.activeGroupTitle
                    font.pointSize: Appearance.font.size.large
                    font.weight: Font.DemiBold
                    color: Colours.palette.m3onSurface
                }

                // Chord keys grid (wrapping flow)
                Flow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Config.keychords.sizes.maxWidth

                    spacing: Appearance.spacing.small

                    Repeater {
                        model: KeyChordsService.activeChords

                        ChordKey {
                            required property var modelData

                            keyLetter: modelData.key
                            label: modelData.label

                            // Each chord key takes equal share of the row
                            width: (Config.keychords.sizes.maxWidth - Appearance.spacing.small) / 2

                            onActivated: {
                                KeyChordsService.handleKey(modelData.key);
                            }
                        }
                    }
                }
            }
        }
    }
}
