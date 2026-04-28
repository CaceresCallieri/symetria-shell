pragma ComponentBehavior: Bound

import ".."
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Dropdown menu surface — uses PillSurface so the menu itself participates in
// the claymorphism family (two-shadow depth + hairline border + top rim) rather
// than a flat single-shadow Elevation. Radius stays small for a card feel; the
// PillSurface defaults can be overridden if a different depth is wanted later.
PillSurface {
    id: root

    property list<MenuItem> items
    property MenuItem active: items[0] ?? null
    property bool expanded

    signal itemSelected(item: MenuItem)

    // Match the shell's outer corner radius (Config.border.rounding ==
    // Appearance.rounding.large == 25, which mirrors Hyprland's window
    // rounding of 24) so the dropdown reads as part of the same panel family.
    radius: Appearance.rounding.large
    color: Colours.palette.m3surfaceContainer

    implicitWidth: Math.max(200, column.implicitWidth + Appearance.padding.normal * 2)
    implicitHeight: root.expanded ? column.implicitHeight + Appearance.padding.normal * 2 : 0
    opacity: root.expanded ? 1 : 0

    ColumnLayout {
        id: column

        // Inset all four sides so menu items don't crash into the now-large
        // rounded corners; their own hover fills also stay clear of the curve.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Appearance.padding.normal
        anchors.rightMargin: Appearance.padding.normal
        anchors.topMargin: Appearance.padding.normal
        spacing: 0

        Repeater {
            model: root.items

            StyledRect {
                id: item

                required property int index
                required property MenuItem modelData
                readonly property bool active: modelData === root.active

                Layout.fillWidth: true
                implicitWidth: menuOptionRow.implicitWidth + Appearance.padding.normal * 2
                implicitHeight: menuOptionRow.implicitHeight + Appearance.padding.normal * 2

                color: active ? Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.medium).background : "transparent"

                StateLayer {
                    color: Colours.palette.m3onSurface
                    disabled: !root.expanded

                    function onClicked(): void {
                        root.itemSelected(item.modelData);
                        root.active = item.modelData;
                        root.expanded = false;
                    }
                }

                RowLayout {
                    id: menuOptionRow

                    anchors.fill: parent
                    anchors.margins: Appearance.padding.normal
                    spacing: Appearance.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: item.modelData.icon
                        color: item.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        text: item.modelData.text
                        color: Colours.palette.m3onSurface
                    }

                    Loader {
                        Layout.alignment: Qt.AlignVCenter
                        active: item.modelData.trailingIcon.length > 0
                        visible: active

                        sourceComponent: MaterialIcon {
                            text: item.modelData.trailingIcon
                            color: Colours.palette.m3onSurface
                        }
                    }
                }
            }
        }
    }

    Behavior on opacity {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
        }
    }

    Behavior on implicitHeight {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
    }
}
