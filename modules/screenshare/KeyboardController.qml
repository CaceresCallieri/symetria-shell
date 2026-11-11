pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: root

    required property SelectionModel selectionModel
    property TextInput searchInput
    property var controls: [] // intentional var: focusable action items
    property int columns: 1
    property bool helpOpen: false
    property int controlIndex: -1
    property Item helpReturnTarget
    signal confirmRequested
    signal cancelRequested
    signal selectionMoved(int index)

    Item {
        id: sourceFocus
        focus: true
    }

    // Controls consume Tab for their own focus chain before ancestor Keys.
    // Window shortcuts keep mode cycling consistent from every control.
    Shortcut {
        sequence: "Tab"
        onActivated: root.cycleMode(false)
    }
    Shortcut {
        sequence: "Shift+Tab"
        onActivated: root.cycleMode(true)
    }

    function cycleMode(backward: bool): void {
        if (helpOpen)
            return;
        selectionModel.setMode(selectionModel.modeIndex + (backward ? -1 : 1));
        searchInput.text = "";
        focusSources();
    }

    function openHelp(): void {
        helpReturnTarget = searchInput.activeFocus ? searchInput : controls.find(item => item.activeFocus) ?? root;
        helpOpen = true;
        sourceFocus.forceActiveFocus();
    }

    function closeHelp(): void {
        helpOpen = false;
        if (helpReturnTarget)
            helpReturnTarget.forceActiveFocus();
        else
            focusSources();
    }

    function confirm(): void {
        if (root.selectionModel.canConfirm)
            root.confirmRequested();
    }

    function focusSources(): void {
        controlIndex = -1;
        // A FocusScope retains its focused child. Focus a real Item so Escape
        // leaves TextInput instead of keeping the search field active.
        sourceFocus.forceActiveFocus();
    }

    function focusControl(backward: bool): void {
        const step = backward ? -1 : 1;
        controlIndex = (controlIndex + step + controls.length) % controls.length;
        if (!controls[controlIndex].enabled)
            controlIndex = (controlIndex + step + controls.length) % controls.length;
        controls[controlIndex].forceActiveFocus();
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if (root.helpOpen) {
            if ([Qt.Key_Escape, Qt.Key_Question, Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
                root.closeHelp();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            const backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
            root.cycleMode(Boolean(backwards));
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_F6) {
            root.focusControl(Boolean(event.modifiers & Qt.ShiftModifier));
            event.accepted = true;
            return;
        }
        if (root.searchInput.activeFocus) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.focusSources();
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.cancelRequested();
            event.accepted = true;
            return;
        }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        event.accepted = true;
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            root.selectionModel.setMode(event.key - Qt.Key_1);
            root.searchInput.text = "";
            root.focusSources();
        } else if (event.key === Qt.Key_Slash && root.selectionModel.mode !== "region") {
            root.searchInput.forceActiveFocus();
        } else if (event.key === Qt.Key_Question) {
            root.openHelp();
        } else if (event.key === Qt.Key_R) {
            root.selectionModel.remember = !root.selectionModel.remember;
        } else if (root.controls.some(item => item.activeFocus)) {
            const control = root.controls.find(item => item.activeFocus);
            if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key) && typeof control.click === "function")
                control.click();
            else
                event.accepted = false;
        } else if ([Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
            root.confirm();
        } else if (event.key === Qt.Key_Delete) {
            root.selectionModel.region = null;
        } else if (event.key === Qt.Key_Home || event.key === Qt.Key_G) {
            root.selectionModel.currentIndex = event.modifiers & Qt.ShiftModifier ? Math.max(0, root.selectionModel.items.length - 1) : 0;
        } else if (event.key === Qt.Key_End) {
            root.selectionModel.currentIndex = Math.max(0, root.selectionModel.items.length - 1);
        } else {
            const horizontal = [Qt.Key_H, Qt.Key_Left].includes(event.key) ? -1 : [Qt.Key_L, Qt.Key_Right].includes(event.key) ? 1 : 0;
            const vertical = [Qt.Key_K, Qt.Key_Up].includes(event.key) ? -1 : [Qt.Key_J, Qt.Key_Down].includes(event.key) ? 1 : 0;
            if (horizontal || vertical) {
                root.selectionModel.move(horizontal, vertical, root.columns, Boolean(event.modifiers & Qt.ShiftModifier));
                root.selectionMoved(root.selectionModel.currentIndex);
            } else {
                event.accepted = false;
            }
        }
    }
}
