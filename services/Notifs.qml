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
                    actions: n.actions,
                    syncTag: n.syncTag
                }))))
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    // Shared image-extension validator used by both the arrival observability log
    // (onNotification) and Notif.isValidImagePath(). Keeping one canonical list
    // prevents the two call-sites from drifting when a new extension is added.
    function _isValidImageExt(path: string): bool {
        if (!path) return false;
        const validExts = [".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif"];
        const lower = path.toLowerCase().split('?')[0].split('#')[0];
        return validExts.some(ext => lower.endsWith(ext));
    }

    // Read the self-supersede tag out of a notification's hints, "" when absent.
    //
    // A client that emits one notification per keypress — a volume or brightness
    // script, a progress bar — wants only the newest on screen. `replaces_id`
    // cannot express that: each keypress is a separate short-lived process, so it
    // would have to persist the server-assigned id across invocations and re-learn
    // it whenever the shell restarts and the id counter resets. The `synchronous`
    // hint moves that bookkeeping to the server, where it belongs.
    //
    // Three spellings are in circulation and clients pick one without probing:
    // libnotify's `--hint string:synchronous:`, GNOME's legacy
    // `x-canonical-private-synchronous`, and dunst's `x-dunst-stack-tag`. Accept
    // all three so a client already working under dunst or mako works here
    // unchanged. Keep this list in step with `server.extraHints`, which is what
    // GetCapabilities advertises over D-Bus.
    function _syncTag(hints: var): string {
        return hints["synchronous"] ?? hints["x-canonical-private-synchronous"] ?? hints["x-dunst-stack-tag"] ?? "";
    }

    // Close the notification that an incoming one supersedes, if any.
    //
    // Scoped by appName as well as by tag, matching dunst. "volume" is an obvious
    // tag for any app to pick, and two unrelated clients that happen to choose it
    // must not close each other's notifications.
    //
    // Uses close() rather than splicing root.list directly, deliberately: close()
    // honours `locks`, so a card that is mid-animation is only marked closed and
    // is destroyed later by its own delegate teardown (Notification.qml unlocks in
    // Component.onDestruction) instead of being torn out from under the renderer.
    // Because notClosed excludes it immediately, the superseded notification also
    // leaves the persisted history right away — see the note on Notif.syncTag.
    function _supersedeSynchronous(tag: string, appName: string): void {
        if (!tag)
            return;
        // At most one live notification per (tag, appName) exists by construction,
        // so the first match is the only match.
        root.list.find(n => !n.closed && n.syncTag === tag && n.appName === appName)?.close();
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

        // Advertised through GetCapabilities so a client can discover the
        // self-supersede support instead of assuming it. Keep in step with the
        // spellings root._syncTag() accepts.
        extraHints: ["synchronous", "x-canonical-private-synchronous", "x-dunst-stack-tag"]

        onNotification: notif => {
            notif.tracked = true;

            // Observability: capture every raw input that affects icon
            // resolution. Used to diagnose blank-disc renders (esp. from
            // Electron clients like Altus that may send pixel-data or
            // extension-less temp paths). Grep `[notif-debug] arrival` to
            // correlate against later image-load failures.
            const ipHint = notif.hints["image-path"] ?? "";
            const idHint = notif.hints["image-data"];
            const legacyIconData = notif.hints["icon_data"];
            const ipValid = ipHint && root._isValidImageExt(ipHint);
            const syncTag = root._syncTag(notif.hints);
            console.log(`[notif-debug] arrival id=${notif.id} appName='${notif.appName}'`,
                `appIcon='${notif.appIcon}'`,
                `image='${(notif.image || "").slice(0, 120)}'`,
                `hint.image-path='${ipHint}' ipValid=${ipValid}`,
                `hint.image-data=${idHint !== undefined}`,
                `hint.icon_data=${legacyIconData !== undefined}`,
                `syncTag='${syncTag}'`);

            // Before inserting, retire whatever this one supersedes. Runs first so
            // the new notification is never briefly stacked on top of the old one.
            root._supersedeSynchronous(syncTag, notif.appName);

            const comp = notifComp.createObject(root, {
                popup: !props.dnd && ![...Visibilities.screens.values()].some(v => v.sidebar),
                notification: notif
            });

            const max = Config.notifs.maxStored;
            // Assign new list first so that dismiss()→onClosed→close() won't find
            // evicted items in root.list and trigger a redundant list.filter() pass.
            const base = root.list.length >= max ? root.list.slice(0, max - 1) : root.list;
            const evicted = root.list.slice(base.length);
            root.list = [comp, ...base];
            for (const n of evicted) {
                n.notification?.dismiss();
                n.destroy();
            }
        }
    }

    FileView {
        id: storage

        path: `${Paths.state}/notifs.json`
        onLoaded: {
            let data;
            try {
                data = JSON.parse(text());
            } catch (e) {
                console.warn("Notifs: failed to parse notifs.json, starting fresh:", e);
                root.loaded = true;
                return;
            }
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

        // Self-supersede tag from the `synchronous` hint family, "" when the
        // client sent none. Persisted alongside the rest so a tag still matches
        // across a shell restart: without it a "Volume: 70%" entry restored from
        // disk would sit in history forever beside every later volume step,
        // because the incoming one would find nothing to supersede.
        property string syncTag

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
                        // Observability: log Error/Null on the pixel-data
                        // loader. If this fires, notif.image will remain the
                        // raw image:// URL and the visible Image at render
                        // time will also fail (blank disc symptom).
                        if (status === Image.Error || status === Image.Null) {
                            console.warn(`[notif-debug] dummy-image-failed id=${notif.id} appName='${notif.appName}'`,
                                `source='${(source.toString() || "").slice(0, 120)}' status=${status}`);
                            return;
                        }
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

        // Validate that a path has a supported image extension.
        // Delegates to the singleton-level helper so both this method and the
        // arrival-log block in onNotification share one canonical extension list.
        function isValidImagePath(path: string): bool {
            return root._isValidImageExt(path);
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
            // Restored-from-disk notifications never reach here (the guard above
            // returns when `notification` is unset), so their syncTag keeps the
            // value createObject seeded from notifs.json.
            syncTag = root._syncTag(notification.hints);
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
