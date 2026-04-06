pragma Singleton
pragma ComponentBehavior: Bound

import qs.components.misc
import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    property list<Notif> list: []
    readonly property list<Notif> notClosed: list.filter(n => !n.closed)
    readonly property list<Notif> popups: list.filter(n => n.popup)
    property alias dnd: props.dnd

    property bool loaded

    onDndChanged: {
        if (!Config.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(qsTr("Do not disturb enabled"), qsTr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(qsTr("Do not disturb disabled"), qsTr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.map(n => ({
                    time: n.time,
                    id: n.id,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    appName: n.appName,
                    image: n.image,
                    expireTimeout: n.expireTimeout,
                    urgency: n.urgency,
                    resident: n.resident,
                    hasActionIcons: n.hasActionIcons,
                    actions: n.actions
                }))))
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            const comp = notifComp.createObject(root, {
                popup: !props.dnd && ![...Visibilities.screens.values()].some(v => v.sidebar),
                notification: notif
            });

            const max = Config.notifs.maxStored;
            if (root.list.length >= max) {
                // Evict oldest beyond cap
                const kept = root.list.slice(0, max - 1);
                for (let i = max - 1; i < root.list.length; i++) {
                    root.list[i].notification?.dismiss();
                    root.list[i].destroy();
                }
                root.list = [comp, ...kept];
            } else {
                root.list = [comp, ...root.list];
            }
        }
    }

    FileView {
        id: storage

        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            // Build array locally to avoid O(n²) binding cascade:
            // each push() triggers list change → notClosed/popups filters re-evaluate
            const loaded = [];
            for (const notif of data)
                loaded.push(notifComp.createObject(root, notif));
            loaded.sort((a, b) => b.time - a.time);
            // Apply cap — discard oldest beyond maxStored
            const max = Config.notifs.maxStored;
            if (loaded.length > max) {
                for (let i = max; i < loaded.length; i++)
                    loaded[i].destroy();
                loaded.length = max;
            }
            root.list = loaded; // Single assignment, single change notification
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                setText("[]");
            }
        }
    }

    // Batch close all notifications for a specific app group.
    // Avoids O(n²) by: (1) NOT setting closed=true on items to destroy
    // (each closed=true triggers notClosed re-eval over entire list),
    // and (2) single list reassignment at the end.
    function closeGroup(appName: string): void {
        const remaining = [];
        const toDestroy = [];
        for (const n of root.list) {
            if (n.appName === appName && !n.closed) {
                if (n.locks.size === 0) {
                    n.notification?.dismiss();
                    toDestroy.push(n);
                } else {
                    n.closed = true;
                    remaining.push(n);
                }
            } else {
                remaining.push(n);
            }
        }
        root.list = remaining;
        for (const n of toDestroy)
            n.destroy();
    }

    // Batch close ALL notifications.
    // Same O(n²) avoidance: only set closed on locked items (rare),
    // destroy the rest after a single list reassignment.
    function clearAll(): void {
        const remaining = [];
        const toDestroy = [];
        for (const n of root.list) {
            if (n.locks.size === 0) {
                n.notification?.dismiss();
                toDestroy.push(n);
            } else {
                n.closed = true;
                remaining.push(n);
            }
        }
        root.list = remaining;
        for (const n of toDestroy)
            n.destroy();
    }

    CustomShortcut {
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: root.clearAll()
    }

    IpcHandler {
        target: "notifs"

        function clear(): void {
            root.clearAll();
        }

        function isDndEnabled(): bool {
            return props.dnd;
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }
    }

    component Notif: QtObject {
        id: notif

        property bool popup
        property bool closed
        property var locks: new Set()

        property date time: new Date()
        readonly property string timeStr: {
            const diff = Time.date.getTime() - time.getTime();
            const m = Math.floor(diff / 60000);

            if (m < 1)
                return qsTr("now");

            const h = Math.floor(m / 60);
            const d = Math.floor(h / 24);

            if (d > 0)
                return `${d}d`;
            if (h > 0)
                return `${h}h`;
            return `${m}m`;
        }

        property Notification notification
        property string id
        property string summary
        property string body
        property string appIcon
        property string appName
        property string image
        property real expireTimeout: Config.notifs.defaultExpireTimeout
        property int urgency: NotificationUrgency.Normal
        property bool resident
        property bool hasActionIcons
        property list<var> actions

        readonly property Timer timer: Timer {
            running: true
            interval: notif.expireTimeout > 0 ? notif.expireTimeout : Config.notifs.defaultExpireTimeout
            onTriggered: {
                if (Config.notifs.expire)
                    notif.popup = false;
            }
        }

        readonly property LazyLoader dummyImageLoader: LazyLoader {
            active: false

            PanelWindow {
                implicitWidth: Config.notifs.sizes.image
                implicitHeight: Config.notifs.sizes.image
                color: "transparent"
                mask: Region {}

                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(notif.image)
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    opacity: 0

                    onStatusChanged: {
                        if (status !== Image.Ready)
                            return;

                        const cacheKey = notif.appName + notif.summary + notif.id;
                        let h1 = 0xdeadbeef, h2 = 0x41c6ce57, ch;
                        for (let i = 0; i < cacheKey.length; i++) {
                            ch = cacheKey.charCodeAt(i);
                            h1 = Math.imul(h1 ^ ch, 2654435761);
                            h2 = Math.imul(h2 ^ ch, 1597334677);
                        }
                        h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
                        h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
                        h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
                        h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);
                        const hash = (h2 >>> 0).toString(16).padStart(8, 0) + (h1 >>> 0).toString(16).padStart(8, 0);

                        const cache = `${Paths.notifimagecache}/${hash}.png`;
                        CUtils.saveItem(this, Qt.resolvedUrl(cache), () => {
                            notif.image = cache;
                            notif.dummyImageLoader.active = false;
                        });
                    }
                }
            }
        }

        readonly property Connections conn: Connections {
            target: notif.notification

            function onClosed(): void {
                notif.close();
            }

            function onSummaryChanged(): void {
                notif.summary = notif.notification.summary;
            }

            function onBodyChanged(): void {
                notif.body = notif.notification.body;
            }

            function onAppIconChanged(): void {
                // Use image-path hint if available and valid, fall back to appIcon
                const imagePath = notif.notification.hints["image-path"] ?? "";
                const validPath = imagePath && notif.isValidImagePath(imagePath);
                notif.appIcon = validPath ? imagePath : notif.notification.appIcon;
            }

            function onAppNameChanged(): void {
                notif.appName = notif.notification.appName;
            }

            function onImageChanged(): void {
                // Don't use notification.image if image-path hint is used as appIcon
                const imagePath = notif.notification.hints["image-path"] ?? "";
                const validPath = imagePath && notif.isValidImagePath(imagePath);
                notif.image = validPath ? "" : notif.notification.image;
                if (notif.image)
                    notif.dummyImageLoader.active = true;
            }

            function onExpireTimeoutChanged(): void {
                notif.expireTimeout = notif.notification.expireTimeout;
            }

            function onUrgencyChanged(): void {
                notif.urgency = notif.notification.urgency;
            }

            function onResidentChanged(): void {
                notif.resident = notif.notification.resident;
            }

            function onHasActionIconsChanged(): void {
                notif.hasActionIcons = notif.notification.hasActionIcons;
            }

            function onActionsChanged(): void {
                notif.actions = notif.notification.actions.map(a => ({
                            identifier: a.identifier,
                            text: a.text,
                            invoke: () => a.invoke()
                        }));
            }
        }

        function lock(item: Item): void {
            locks.add(item);
        }

        function unlock(item: Item): void {
            locks.delete(item);
            if (closed)
                close();
        }

        function close(): void {
            closed = true;
            if (locks.size === 0 && root.list.includes(this)) {
                root.list = root.list.filter(n => n !== this);
                notification?.dismiss();
                destroy();
            }
        }

        // Validate that a path has a supported image extension
        function isValidImagePath(path: string): bool {
            if (!path) return false;
            const validExts = [".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif"];
            const lower = path.toLowerCase().split('?')[0].split('#')[0];  // Strip query params
            return validExts.some(ext => lower.endsWith(ext));
        }

        Component.onCompleted: {
            if (!notification)
                return;

            id = notification.id;
            summary = notification.summary;
            body = notification.body;
            // Use image-path hint if available and valid (for absolute paths from notify-send --icon)
            // Fall back to appIcon (for icon theme names)
            const imagePath = notification.hints["image-path"] ?? "";
            const validPath = imagePath && isValidImagePath(imagePath);
            appIcon = validPath ? imagePath : notification.appIcon;
            appName = notification.appName;
            // Don't use notification.image if we're using image-path as appIcon (avoid duplicate display)
            image = validPath ? "" : notification.image;
            if (image)
                dummyImageLoader.active = true;
            expireTimeout = notification.expireTimeout;
            urgency = notification.urgency;
            resident = notification.resident;
            hasActionIcons = notification.hasActionIcons;
            actions = notification.actions.map(a => ({
                        identifier: a.identifier,
                        text: a.text,
                        invoke: () => a.invoke()
                    }));
        }
    }

    Component {
        id: notifComp

        Notif {}
    }
}
