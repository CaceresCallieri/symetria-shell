pragma ComponentBehavior: Bound

import ".."
import qs.components
import qs.services
import qs.config
import QtQuick

Item {
    id: root

    property string text: ""
    property var validator: null // intentional var: nullable QML Validator (IntValidator, RegularExpressionValidator, etc.)
    property bool readOnly: false
    property int horizontalAlignment: TextInput.AlignHCenter

    // `implicitWidth` and `enabled` are ASSIGNED here, never re-declared.
    // Both already exist on Item, and `property <type> implicitWidth` /
    // `property bool enabled` create SHADOW properties instead of setting them:
    // Qt logs "Member ... overrides a member of the base object", layouts keep
    // reading the (unset, 0) base implicitWidth, and `enabled` stops
    // propagating to the subtree the way Item.enabled does. See
    // docs/qml-pitfalls.md (required property shadowing) — same failure mode.
    implicitWidth: 70

    // Expose activeFocus through alias to avoid FINAL property override
    readonly property alias hasFocus: inputField.activeFocus

    signal textEdited(string text)
    signal editingFinished()

    implicitHeight: inputField.implicitHeight + Appearance.padding.small * 2

    StyledRect {
        id: container

        anchors.fill: parent
        color: inputHover.containsMouse || inputField.activeFocus 
               ? Colours.layer(Colours.palette.m3surfaceContainer, 3)
               : Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Appearance.rounding.small
        border.width: 1
        border.color: inputField.activeFocus 
                      ? Colours.palette.m3primary
                      : Qt.alpha(Colours.palette.m3outline, 0.3)
        opacity: root.enabled ? 1 : 0.5

        Behavior on color { CAnim {} }
        Behavior on border.color { CAnim {} }

        MouseArea {
            id: inputHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            acceptedButtons: Qt.NoButton
        }

        StyledTextField {
            id: inputField
            anchors.centerIn: parent
            width: parent.width - Appearance.padding.normal
            horizontalAlignment: root.horizontalAlignment
            validator: root.validator
            readOnly: root.readOnly
            
            Binding {
                target: inputField
                property: "text"
                value: root.text
                when: !inputField.activeFocus
            }
            
            onTextChanged: {
                root.text = text;
                root.textEdited(text);
            }
            
            onEditingFinished: {
                root.editingFinished();
            }
        }
    }
}

