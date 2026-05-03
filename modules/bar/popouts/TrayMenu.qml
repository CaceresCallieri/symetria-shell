pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

StackView {
    id: root

    required property Item popouts
    required property QsMenuHandle trayItem

    implicitWidth: currentItem.implicitWidth
    implicitHeight: currentItem.implicitHeight

    initialItem: SubMenu {
        handle: root.trayItem
    }

    pushEnter: NoAnim {}
    pushExit: NoAnim {}
    popEnter: NoAnim {}
    popExit: NoAnim {}

    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }

    component SubMenu: Column {
        id: menu

        required property QsMenuHandle handle
        property bool isSubMenu
        property bool shown

        // Split menuOpener.children on `isSeparator` boundaries so each
        // separator-delimited section becomes its own claymorphism card.
        // The native menu protocol already encodes section structure via
        // separators; we consume that signal here instead of painting it
        // as a 1px line.
        // intentional var: array of arrays of QsMenuEntry from QsMenuOpener
        readonly property var groupedEntries: {
            const groups = [];
            let current = [];
            // Quickshell typed list properties expose `.values` for JS iteration.
            // The bare `menuOpener.children` works as a Repeater model but not as
            // an iterable here, and accessing it without `.values` fails to register
            // dependency tracking — the binding would never re-fire when the menu
            // populates asynchronously after open.
            const list = menuOpener.children.values;
            for (let i = 0; i < list.length; i++) {
                const entry = list[i];
                if (entry.isSeparator) {
                    if (current.length > 0) {
                        groups.push(current);
                        current = [];
                    }
                } else {
                    current.push(entry);
                }
            }
            if (current.length > 0)
                groups.push(current);
            return groups;
        }

        padding: Appearance.padding.smaller
        spacing: Appearance.spacing.small

        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.8

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {}
        }

        QsMenuOpener {
            id: menuOpener

            menu: menu.handle
        }

        Repeater {
            model: menu.groupedEntries

            Item {
                id: groupCard

                // intentional var: array of QsMenuEntry — one separator-delimited section
                required property var modelData

                implicitWidth: Config.bar.sizes.trayMenuWidth
                implicitHeight: groupColumn.implicitHeight + Appearance.padding.large * 2

                PillCard {
                    anchors.fill: parent
                }

                Column {
                    id: groupColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Appearance.padding.large
                    anchors.rightMargin: Appearance.padding.large
                    spacing: Appearance.spacing.small

                    Repeater {
                        model: groupCard.modelData

                        StyledRect {
                            id: item

                            required property QsMenuEntry modelData

                            width: parent.width
                            implicitHeight: itemContent.implicitHeight

                            radius: Appearance.rounding.full
                            color: "transparent"

                            Loader {
                                id: itemContent

                                anchors.left: parent.left
                                anchors.right: parent.right

                                asynchronous: true

                                sourceComponent: Item {
                                    implicitHeight: label.implicitHeight

                                    StateLayer {
                                        anchors.margins: -Appearance.padding.small / 2
                                        anchors.leftMargin: -Appearance.padding.smaller
                                        anchors.rightMargin: -Appearance.padding.smaller

                                        radius: item.radius
                                        disabled: !item.modelData.enabled

                                        function onClicked(): void {
                                            const entry = item.modelData;
                                            if (entry.hasChildren)
                                                root.push(subMenuComp.createObject(null, {
                                                    handle: entry,
                                                    isSubMenu: true
                                                }));
                                            else {
                                                item.modelData.triggered();
                                                root.popouts.hasCurrent = false;
                                            }
                                        }
                                    }

                                    Loader {
                                        id: icon

                                        anchors.left: parent.left

                                        active: item.modelData.icon !== ""
                                        asynchronous: true

                                        sourceComponent: IconImage {
                                            // Minimum 16px to prevent invalid icon requests during initialization
                                            implicitSize: Math.max(label.implicitHeight, 16)

                                            source: item.modelData.icon
                                        }
                                    }

                                    StyledText {
                                        id: label

                                        anchors.left: icon.right
                                        anchors.leftMargin: icon.active ? Appearance.spacing.smaller : 0

                                        text: labelMetrics.elidedText
                                        color: item.modelData.enabled ? Colours.palette.m3onSurface : Colours.palette.m3outline
                                    }

                                    TextMetrics {
                                        id: labelMetrics

                                        text: item.modelData.text
                                        font.pointSize: label.font.pointSize
                                        font.family: label.font.family

                                        elide: Text.ElideRight
                                        elideWidth: item.width - (icon.active ? icon.implicitWidth + label.anchors.leftMargin : 0) - (expand.active ? expand.implicitWidth + Appearance.spacing.normal : 0)
                                    }

                                    Loader {
                                        id: expand

                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right

                                        active: item.modelData.hasChildren
                                        asynchronous: true

                                        sourceComponent: MaterialIcon {
                                            text: "chevron_right"
                                            color: item.modelData.enabled ? Colours.palette.m3onSurface : Colours.palette.m3outline
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            active: menu.isSubMenu
            asynchronous: true

            sourceComponent: Item {
                implicitWidth: back.implicitWidth
                implicitHeight: back.implicitHeight + Appearance.spacing.small / 2

                Item {
                    anchors.bottom: parent.bottom
                    implicitWidth: back.implicitWidth
                    implicitHeight: back.implicitHeight

                    StyledRect {
                        anchors.fill: parent
                        anchors.margins: -Appearance.padding.small / 2
                        anchors.leftMargin: -Appearance.padding.smaller
                        anchors.rightMargin: -Appearance.padding.smaller * 2

                        radius: Appearance.rounding.full
                        color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onSurface

                            function onClicked(): void {
                                root.pop();
                            }
                        }
                    }

                    Row {
                        id: back

                        anchors.verticalCenter: parent.verticalCenter

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "chevron_left"
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Back")
                            color: Colours.palette.m3onSurface
                        }
                    }
                }
            }
        }
    }

    Component {
        id: subMenuComp

        SubMenu {}
    }
}
