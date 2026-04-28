pragma ComponentBehavior: Bound

import qs.components
import qs.components.misc
import qs.services
import qs.config
import qs.utils
import Quickshell
import QtQuick

Row {
    id: root

    required property PersistentProperties visibilities

    padding: Appearance.padding.large
    spacing: Appearance.spacing.large

    FocusManager {
        active: root.visibilities.session
        target: logout
    }

    Keys.onPressed: event => {
        if (event.modifiers !== Qt.NoModifier)
            return;
        switch (event.key) {
        case Qt.Key_L:
            Quickshell.execDetached(Config.session.commands.logout);
            event.accepted = true;
            break;
        case Qt.Key_P:
            Quickshell.execDetached(Config.session.commands.shutdown);
            event.accepted = true;
            break;
        case Qt.Key_S:
            Quickshell.execDetached(Config.session.commands.suspend);
            event.accepted = true;
            break;
        case Qt.Key_R:
            Quickshell.execDetached(Config.session.commands.reboot);
            event.accepted = true;
            break;
        }
    }

    SessionButton {
        id: logout

        icon: "logout"
        command: Config.session.commands.logout

        KeyNavigation.right: shutdown
    }

    SessionButton {
        id: shutdown

        icon: "power_settings_new"
        command: Config.session.commands.shutdown

        KeyNavigation.left: logout
        KeyNavigation.right: suspend
    }

    SessionButton {
        id: suspend

        icon: "bedtime"
        command: Config.session.commands.suspend

        KeyNavigation.left: shutdown
        KeyNavigation.right: reboot
    }

    SessionButton {
        id: reboot

        icon: "cached"
        command: Config.session.commands.reboot

        KeyNavigation.left: suspend
    }

    component SessionButton: Item {
        id: button

        required property string icon
        required property list<string> command

        implicitWidth: Config.session.sizes.button
        implicitHeight: Config.session.sizes.button

        // Compute pill style once per focus state — PillSurface needs both
        // .background and .border, so calling pillStyle() twice would run the
        // same pure computation twice for no benefit.
        readonly property var _pillStyle: button.activeFocus
            ? Colours.pillStyle(Colours.palette.m3secondaryContainer, Colours.glass.subtle)
            : Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

        Keys.onEnterPressed: Quickshell.execDetached(button.command)
        Keys.onReturnPressed: Quickshell.execDetached(button.command)
        Keys.onEscapePressed: root.visibilities.session = false
        Keys.onPressed: event => {
            // Tab/Backtab are universal accessibility navigation — not vim-specific.
            if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                if (KeyNavigation.right) {
                    KeyNavigation.right.focus = true;
                    event.accepted = true;
                }
                return;
            }
            if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                if (KeyNavigation.left) {
                    KeyNavigation.left.focus = true;
                    event.accepted = true;
                }
                return;
            }

            if (!Config.session.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_L && KeyNavigation.right) {
                    KeyNavigation.right.focus = true;
                    event.accepted = true;
                } else if (event.key === Qt.Key_H && KeyNavigation.left) {
                    KeyNavigation.left.focus = true;
                    event.accepted = true;
                }
            }
        }

        PillSurface {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: button._pillStyle.background
            borderColor: button._pillStyle.border
        }

        StateLayer {
            radius: Appearance.rounding.full
            color: button.activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface

            function onClicked(): void {
                Quickshell.execDetached(button.command);
            }
        }

        MaterialIcon {
            anchors.centerIn: parent

            text: button.icon
            color: button.activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            font.pointSize: Appearance.font.size.extraLarge
            font.weight: 500
        }
    }
}
