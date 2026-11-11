import QtQuick
import QtQuick.Controls
import QtTest
import "../../../modules/screenshare" as ScreenShare

TestCase {
    id: test
    name: "NativeScreenShare"
    when: windowShown
    width: 900
    height: 700

    ScreenShare.SelectionModel {
        id: selection
    }
    ScreenShare.KeyboardController {
        id: keys
        width: 900
        height: 700
        selectionModel: selection
        searchInput: search
        columns: 6
        controls: [action]
        property int confirmed: 0
        property int cancelled: 0
        onConfirmRequested: confirmed++
        onCancelRequested: cancelled++
        TextInput {
            id: search
            width: 200
            height: 40
            Keys.forwardTo: [keys]
            onTextEdited: selection.setQuery(text)
        }
        Button {
            id: action
            y: 45
            text: "Action"
            property int presses: 0
            Keys.forwardTo: [keys]
            onClicked: presses++
        }
    }
    ScreenShare.RegionPreview {
        id: preview
        x: 0
        y: 100
        width: 600
        height: 400
        selectionModel: selection
    }

    function init() {
        const windows = [];
        for (let i = 0; i < 31; i++)
            windows.push({
                id: `window:${i}`,
                title: `Window ${i}`,
                app: "App",
                detail: "Work"
            });
        selection.load({
            sources: {
                windows,
                screens: [
                    {
                        id: "screen:a",
                        title: "a"
                    }
                ],
                workspaces: []
            },
            outputs: [
                {
                    name: "land",
                    width: 2560,
                    height: 1600
                },
                {
                    name: "portrait",
                    width: 1080,
                    height: 1920
                },
                {
                    name: "wide",
                    width: 3440,
                    height: 1440
                }
            ],
            preferredOutput: "land",
            rememberDefault: true
        });
        keys.helpOpen = false;
        keys.confirmed = 0;
        keys.cancelled = 0;
        action.presses = 0;
        search.text = "";
        keys.focusSources();
    }

    function test_modes_and_grid_boundaries() {
        keyClick(Qt.Key_Tab);
        compare(selection.modeIndex, 1);
        keyClick(Qt.Key_Backtab);
        compare(selection.modeIndex, 0);
        keyClick(Qt.Key_4);
        compare(selection.mode, "region");
        keyClick(Qt.Key_1);
        keyClick(Qt.Key_J);
        compare(selection.currentIndex, 6);
        keyClick(Qt.Key_Left);
        compare(selection.currentIndex, 6);
        keyClick(Qt.Key_Right);
        compare(selection.currentIndex, 7);
        keys.columns = 3;
        keyClick(Qt.Key_Down);
        compare(selection.currentIndex, 10);
        keys.columns = 6;
    }

    function test_search_controls_and_help() {
        keyClick(Qt.Key_Slash);
        verify(search.activeFocus);
        keyClick(Qt.Key_Q);
        keyClick(Qt.Key_1);
        keyClick(Qt.Key_Question);
        compare(search.text, "q1?");
        compare(selection.modeIndex, 0);
        compare(keys.cancelled, 0);
        keyClick(Qt.Key_Escape);
        verify(keys.activeFocus);
        verify(!search.activeFocus);
        keyClick(Qt.Key_F6);
        verify(action.activeFocus);
        keyClick(Qt.Key_Return);
        compare(action.presses, 1);
        compare(keys.confirmed, 0);
        keyClick(Qt.Key_Tab);
        compare(selection.modeIndex, 1);
        verify(keys.activeFocus);
        keyClick(Qt.Key_F6);
        verify(action.activeFocus);
        keyClick(Qt.Key_Question);
        verify(keys.helpOpen);
        keyClick(Qt.Key_Tab);
        compare(selection.modeIndex, 1);
        keyClick(Qt.Key_Escape);
        verify(!keys.helpOpen);
        verify(action.activeFocus);
    }

    function test_confirm_cancel_and_remember() {
        verify(selection.remember);
        keyClick(Qt.Key_R);
        verify(!selection.remember);
        keyClick(Qt.Key_Return);
        compare(keys.confirmed, 1);
        keyClick(Qt.Key_Escape);
        compare(keys.cancelled, 1);
    }

    function test_region_geometry_and_reset() {
        selection.setMode(3);
        verify(!selection.canConfirm);
        keyClick(Qt.Key_Right);
        verify(selection.canConfirm);
        const width = selection.region.width;
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        verify(selection.region.width < width);
        selection.dragRegion(0.8, 0.9, 0.1, 0.2);
        fuzzyCompare(selection.region.x, 0.1, 0.00001);
        fuzzyCompare(selection.region.width, 0.7, 0.00001);
        keyClick(Qt.Key_Delete);
        verify(!selection.canConfirm);
        selection.dragRegion(0, 0, 1, 1);
        selection.selectOutput(1);
        compare(selection.region, null);
    }

    function test_region_fit() {
        for (let output = 0; output < 3; output++) {
            selection.selectOutput(output);
            for (const size of [[600, 400], [300, 500], [1200, 300]]) {
                preview.width = size[0];
                preview.height = size[1];
                verify(preview.stageWidth <= preview.width + 0.1);
                verify(preview.stageHeight <= preview.height + 0.1);
                fuzzyCompare(preview.stageWidth / preview.stageHeight, selection.output.width / selection.output.height, 0.00001);
            }
        }
    }
}
