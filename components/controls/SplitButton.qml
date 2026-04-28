import ".."
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Two adjacent claymorphism pills: a selector pill (left, always raised) and
// an expander pill (right, raised when closed → inset when the menu is open).
// The "menu open" cue reuses the inverse-neumorphism inset depth from the
// Quick Toggles so the SplitButton speaks the same visual language.
//
// Root is Item (not Row) because the dropdown Menu must escape PillToggleSurface's
// ClippingRectangle body — otherwise it gets clipped to the pill's bounds. Placing
// it as a sibling of the two halves at the SplitButton root level keeps it free.
Item {
    id: root

    enum Type {
        Filled,
        Tonal
    }

    property real horizontalPadding: Appearance.padding.normal
    property real verticalPadding: Appearance.padding.smaller
    property int type: SplitButton.Filled
    property bool disabled
    property bool loading
    property bool menuOnTop
    property string fallbackIcon
    property string fallbackText

    property alias menuItems: menu.items
    property alias active: menu.active
    property alias expanded: menu.expanded
    property alias menu: menu
    property alias iconLabel: iconLabel
    property alias label: label
    property alias stateLayer: stateLayer

    // Match the inactive Quick Toggle body fill so SplitButton halves sit in
    // the same tonal family as the row of toggles below them. The previous
    // Filled variant used a Qt.lighter()×1.5 + glass.medium fill that read as
    // "selected/emphasis" — but now that the chevron's `expanded` cue uses
    // the inverse-neumorphism inset (and the Quick Toggles brighten on active),
    // colour-emphasis is no longer carrying state and just made the SplitButton
    // pop louder than the surrounding pills. Both Filled and Tonal types now
    // share the same matte body; type retains semantic meaning if a consumer
    // wants to override.
    property color colour: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background
    property color textColour: Colours.palette.m3onSurface
    property color disabledColour: Qt.alpha(Colours.palette.m3onSurface, 0.1)
    property color disabledTextColour: Qt.alpha(Colours.palette.m3onSurface, 0.38)

    readonly property real _gap: Appearance.spacing.small

    implicitWidth: selector.implicitWidth + _gap + expandBtn.implicitWidth
    implicitHeight: expandBtn.implicitHeight

    PillToggleSurface {
        id: selector

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        raised: true
        active: false
        // Body color is constant — selector half never changes state, so we
        // wire activeColor to the same value to keep CAnim bindings inert.
        inactiveColor: root.disabled ? root.disabledColour : root.colour
        activeColor: inactiveColor
        radius: implicitHeight / 2 * Math.min(1, Appearance.rounding.scale)

        implicitWidth: textRow.implicitWidth + root.horizontalPadding * 2
        implicitHeight: expandBtn.implicitHeight

        StateLayer {
            id: stateLayer

            // contentHolder (StateLayer's actual parent) has no radius, so the
            // implicit `parent.radius` fallback in StateLayer would clip to 0.
            // Bind directly to the surface radius so hover/press feedback hugs
            // the pill shape.
            radius: selector.radius
            color: root.textColour
            disabled: root.disabled

            function onClicked(): void {
                root.active?.clicked();
            }
        }

        RowLayout {
            id: textRow

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: Math.floor(root.verticalPadding / 4)
            spacing: Appearance.spacing.small

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: iconLabel.implicitWidth
                implicitHeight: iconLabel.implicitHeight

                MaterialIcon {
                    id: iconLabel

                    anchors.centerIn: parent
                    animate: true
                    text: root.active?.activeIcon ?? root.fallbackIcon
                    color: root.disabled ? root.disabledTextColour : root.textColour
                    fill: 1
                    opacity: root.loading ? 0 : 1

                    Behavior on opacity {
                        Anim {}
                    }
                }

                Loader {
                    anchors.centerIn: parent
                    active: root.loading
                    sourceComponent: CircularIndicator {
                        implicitSize: iconLabel.implicitHeight
                        strokeWidth: Appearance.padding.small * 0.5
                        fgColour: Colours.palette.m3onSurface
                        bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.3)
                        running: true
                    }
                }
            }

            StyledText {
                id: label

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: implicitWidth
                animate: true
                text: root.active?.activeText ?? root.fallbackText
                color: root.disabled ? root.disabledTextColour : root.textColour
                clip: true

                Behavior on Layout.preferredWidth {
                    Anim {
                        easing.bezierCurve: Appearance.anim.curves.emphasized
                    }
                }
            }
        }
    }

    PillToggleSurface {
        id: expandBtn

        anchors.left: selector.right
        anchors.leftMargin: root._gap
        anchors.verticalCenter: parent.verticalCenter

        // Press-in cue when the menu is open: PillToggleSurface fades the
        // outer shadows + top rim and paints an inset gradient. Combined with
        // the chevron rotation already below, "expanded" reads unambiguously.
        raised: true
        active: root.expanded
        inactiveColor: root.disabled ? root.disabledColour : root.colour
        activeColor: inactiveColor
        radius: implicitHeight / 2 * Math.min(1, Appearance.rounding.scale)

        implicitWidth: implicitHeight
        implicitHeight: expandIcon.implicitHeight + root.verticalPadding * 2

        StateLayer {
            id: expandStateLayer

            radius: expandBtn.radius
            color: root.textColour
            disabled: root.disabled

            function onClicked(): void {
                root.expanded = !root.expanded;
            }
        }

        MaterialIcon {
            id: expandIcon

            anchors.centerIn: parent
            text: "expand_more"
            color: root.disabled ? root.disabledTextColour : root.textColour
            rotation: root.expanded ? 180 : 0

            Behavior on rotation {
                Anim {}
            }
        }
    }

    // Menu lives outside both PillToggleSurfaces so the ClippingRectangle pill
    // bodies don't crop it. Anchored to expandBtn so it tracks the chevron's
    // edge regardless of layout changes.
    Menu {
        id: menu

        states: State {
            when: root.menuOnTop

            AnchorChanges {
                target: menu
                anchors.top: undefined
                anchors.bottom: expandBtn.top
            }
        }

        anchors.top: expandBtn.bottom
        anchors.right: expandBtn.right
        anchors.topMargin: Appearance.spacing.small
        anchors.bottomMargin: Appearance.spacing.small
    }
}
