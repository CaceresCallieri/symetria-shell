import QtQuick
import QtTest
import NativeShare 1.0
import ScreenShareTest 1.0

TestCase {
    name: "ScreenShareService"
    when: windowShown
    visible: true
    readonly property string token: "a".repeat(64)
    readonly property string path: Bridge.runtimeDirectory + "/symmetria-share-a/request.sock"

    function init() {
        ScreenShare.reset();
        Bridge.socket.connected = false;
        Bridge.socket.messages = [];
        ScreenShare.errorMessage = "";
    }

    function cleanup() {
        Bridge.socket.connected = false;
        ScreenShare.reset();
    }

    function receive(message) {
        Bridge.socket.parser.read(JSON.stringify(Object.assign({
            token
        }, message)));
    }

    function activate() {
        compare(ScreenShare.open(path, token), "accepted");
        receive({
            type: "context",
            context: {
                sources: {},
                outputs: []
            }
        });
        verify(ScreenShare.active);
    }

    function test_invalid_request_data() {
        for (const invalidPath of ["/foreign/symmetria-share-a/request.sock", Bridge.runtimeDirectory + "/symmetria-share-../request.sock", path + "/extra", Bridge.runtimeDirectory + "/symmetria-share-a/../request.sock"]) {
            compare(ScreenShare.open(invalidPath, token), "invalid");
            verify(!ScreenShare.connecting);
            verify(!Bridge.socket.connected);
        }
        for (const invalidToken of ["", "a".repeat(63), "g".repeat(64), "A".repeat(64)])
            compare(ScreenShare.open(path, invalidToken), "invalid");
    }

    function test_busy_during_connect_active_and_cancel() {
        compare(ScreenShare.open(path, token), "accepted");
        verify(ScreenShare.connecting);
        compare(Bridge.socket.path, path);
        compare(ScreenShare.open(path, token), "busy");
        receive({
            type: "context",
            context: {
                sources: {},
                outputs: []
            }
        });
        verify(ScreenShare.active);
        verify(!ScreenShare.connecting);
        compare(ScreenShare.open(path, token), "busy");
        ScreenShare.cancel();
        verify(!ScreenShare.active);
        verify(Bridge.socket.connected);
        compare(Bridge.socket.messages[0].type, "cancel");
        compare(Bridge.socket.messages[0].token, token);
        compare(ScreenShare.open(path, token), "busy");
        Bridge.socket.connected = false;
        compare(ScreenShare.token, "");
        compare(ScreenShare.open(path, token), "accepted");
    }

    function test_disconnect_resets_each_request_phase_data() {
        return [
            {
                tag: "connecting",
                phase: 0
            },
            {
                tag: "active",
                phase: 1
            },
            {
                tag: "submitting",
                phase: 2
            }
        ];
    }

    function test_disconnect_resets_each_request_phase(data) {
        compare(ScreenShare.open(path, token), "accepted");
        if (data.phase > 0)
            receive({
                type: "context",
                context: {
                    sources: {},
                    outputs: []
                }
            });
        if (data.phase > 1)
            ScreenShare.confirm({
                mode: "screens",
                id: "screen:a",
                remember: false
            });
        Bridge.socket.connected = false;
        verify(!ScreenShare.active);
        verify(!ScreenShare.connecting);
        verify(!ScreenShare.submitting);
        compare(ScreenShare.token, "");
        compare(ScreenShare.context, ({}));
        compare(ScreenShare.thumbnails, ({}));
    }

    function test_error_allows_retry_and_done_closes_connection() {
        activate();
        ScreenShare.confirm({
            mode: "screens",
            id: "screen:a",
            remember: false
        });
        verify(ScreenShare.submitting);
        compare(Bridge.socket.messages[0].type, "confirm");
        receive({
            type: "error",
            message: "Source unavailable"
        });
        verify(!ScreenShare.submitting);
        compare(ScreenShare.errorMessage, "Source unavailable");
        ScreenShare.confirm({
            mode: "screens",
            id: "screen:b",
            remember: true
        });
        compare(Bridge.socket.messages[1].id, "screen:b");
        receive({
            type: "done"
        });
        verify(!ScreenShare.active);
        verify(!Bridge.socket.connected);
        verify(!ScreenShare.submitting);
    }

    function test_foreign_replies_and_thumbnail_dispatch() {
        compare(ScreenShare.open(path, token), "accepted");
        receive({
            type: "context",
            token: "foreign",
            context: {}
        });
        verify(ScreenShare.connecting);
        verify(!ScreenShare.active);
        receive({
            type: "context",
            context: {
                sources: {},
                outputs: []
            }
        });
        ScreenShare.requestThumbnail("window:1");
        ScreenShare.requestThumbnail("window:1");
        compare(Bridge.socket.messages.length, 1);
        compare(Bridge.socket.messages[0].type, "thumbnail");
        compare(Bridge.socket.messages[0].id, "window:1");
        receive({
            type: "thumbnail",
            id: "window:1",
            url: "file:///preview.png"
        });
        compare(ScreenShare.thumbnails["window:1"], "file:///preview.png");
    }
}
