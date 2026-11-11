pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// One connection belongs to one XDPH picker process. Its disconnection releases
// the layer and its exclusive focus. Frontend cancellation is an XDPH boundary;
// see docs/screenshare-picker.md before assuming that it ends this connection.
Scope {
    id: root

    property bool active: false
    property bool connecting: false
    property bool submitting: false
    property string token: ""
    property string errorMessage: ""
    property var context: ({}) // intentional var: portal JSON context
    property var thumbnails: ({}) // intentional var: source ID -> file URL
    property var requested: ({}) // intentional var: source ID -> requested flag

    function open(path: string, requestToken: string): string {
        if (active || connecting || bridge.connected)
            return "busy";
        const prefix = Quickshell.env("XDG_RUNTIME_DIR") + "/symmetria-share-";
        const suffix = path.slice(prefix.length);
        if (!path.startsWith(prefix) || !/^[A-Za-z0-9_-]+\/request\.sock$/.test(suffix) || !/^[a-f0-9]{64}$/.test(requestToken))
            return "invalid";
        token = requestToken;
        errorMessage = "";
        connecting = true;
        bridge.path = path;
        bridge.connected = true;
        connectTimeout.restart();
        return "accepted";
    }

    function reset(): void {
        active = false;
        connecting = false;
        submitting = false;
        context = ({});
        thumbnails = ({});
        requested = ({});
        token = "";
        connectTimeout.stop();
    }

    function send(message: var): void {
        if (!bridge.connected)
            return;
        message.token = token;
        bridge.write(JSON.stringify(message) + "\n");
        bridge.flush();
    }

    function confirm(selection: var): void {
        if (!active || submitting)
            return;
        submitting = true;
        selection.type = "confirm";
        send(selection);
    }

    function cancel(): void {
        if (!active)
            return;
        send({
            type: "cancel"
        });
        // Cancellation needs no protocol validation. Drop input immediately.
        active = false;
    }

    function requestThumbnail(identifier: string): void {
        if (!active || requested[identifier])
            return;
        requested = Object.assign({}, requested, {
            [identifier]: true
        });
        send({
            type: "thumbnail",
            id: identifier
        });
    }

    function receive(data: string): void {
        try {
            const message = JSON.parse(data);
            if (message.token !== token)
                return;
            if (message.type === "context" && connecting) {
                context = message.context;
                connecting = false;
                connectTimeout.stop();
                active = true;
            } else if (message.type === "thumbnail") {
                thumbnails = Object.assign({}, thumbnails, {
                    [message.id]: message.url
                });
            } else if (message.type === "error") {
                submitting = false;
                errorMessage = message.message;
            } else if (message.type === "done") {
                reset();
                bridge.connected = false;
            }
        } catch (error) {
            console.warn("ScreenShare: invalid bridge message", error);
            reset();
            bridge.connected = false;
        }
    }

    Socket {
        id: bridge
        connected: false
        parser: SplitParser {
            onRead: data => root.receive(data)
        }
        onConnectionStateChanged: {
            if (!connected)
                root.reset();
        }
    }

    Timer {
        id: connectTimeout
        interval: 10000
        onTriggered: {
            root.reset();
            bridge.connected = false;
        }
    }
}
