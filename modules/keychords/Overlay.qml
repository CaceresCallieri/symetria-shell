pragma ComponentBehavior: Bound

import qs.components
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Bottom-anchored horizontal panel for KeyChords which-key display.
///
/// Shows available chord keys for the active group in a multi-column
/// grid that adapts to content size. Positioned above the agent bar,
/// centered horizontally. Container shrinks to fit when few items.
///
/// Lives as a direct child of StyledWindow in Drawers.qml (not inside
/// Panels) to avoid Region mask issues with click-through.
Item {
    id: root

    required property PersistentProperties visibilities
    required property real bottomOffset

    readonly property bool shouldShow: visibilities.keychords && Config.keychords.enabled && KeyChordsService.active

    // IMPORTANT: The idle value of dialogOpacity MUST reach 0.0 so visible becomes false.
    // When visible: true, the full-window dismiss MouseArea participates in Qt Quick's
    // cursor hit-testing — even with enabled: false. Being the highest z-order sibling
    // in Drawers.qml, its default ArrowCursor shadows every cursorShape below.
    // See: docs/cursor-shape-layer-shell.md
    visible: dialogOpacity > 0

    property real dialogOpacity: shouldShow ? 1.0 : 0.0
    property real dialogTranslateY: shouldShow ? 0 : dialogWrapper.height + root.bottomOffset

    Behavior on dialogOpacity {
        Anim {}
    }

    Behavior on dialogTranslateY {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }
    }

    FocusManager {
        active: root.shouldShow
        target: dialog
    }

    // Transparent click catcher — dismiss when clicking outside the dialog.
    MouseArea {
        anchors.fill: parent
        enabled: root.shouldShow
        onClicked: KeyChordsService.dismiss()
    }

    // Bottom-centered dialog — sized by content, not by screen
    Item {
        id: dialogWrapper

        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomOffset
        anchors.horizontalCenter: parent.horizontalCenter
        width: dialog.implicitWidth
        height: dialog.implicitHeight

        transform: Translate {
            y: root.dialogTranslateY
        }
        opacity: root.dialogOpacity

        StyledRect {
            id: dialog

            implicitWidth: dialogContent.implicitWidth + Appearance.padding.large * 2
            implicitHeight: dialogContent.implicitHeight + Appearance.padding.large * 2

            readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

            radius: Appearance.rounding.normal
            color: glassStyle.background
            border.width: 1
            border.color: glassStyle.border

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
                spacing: Appearance.spacing.normal

                // Group title
                StyledText {
                    Layout.alignment: Qt.AlignHCenter

                    text: KeyChordsService.activeGroupTitle
                    font.pointSize: Appearance.font.size.normal
                    font.weight: Font.DemiBold
                    color: Colours.palette.m3onSurfaceVariant
                }

                // Chord keys grid — columns computed from screen width, container shrinks to fit
                Grid {
                    id: chordGrid

                    Layout.alignment: Qt.AlignHCenter

                    readonly property int targetItemWidth: Config.keychords.sizes.itemWidth
                    readonly property real availableWidth: root.width - Appearance.padding.large * 4
                    columns: Math.max(1, Math.min(
                        KeyChordsService.activeChords.length ?? 1,
                        Math.floor(availableWidth / (targetItemWidth + columnSpacing))
                    ))

                    columnSpacing: Appearance.spacing.small
                    rowSpacing: Appearance.spacing.small

                    Repeater {
                        model: KeyChordsService.activeChords

                        ChordKey {
                            required property var modelData

                            keyLetter: modelData.key
                            label: modelData.label
                            width: Config.keychords.sizes.itemWidth

                            onActivated: {
                                KeyChordsService.dispatchChord(modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
