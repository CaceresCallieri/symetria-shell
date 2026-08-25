pragma ComponentBehavior: Bound

import "../../utils/scripts/fzf.js" as Fzf
import "../../utils/scripts/fuzzysort.js" as Fuzzy
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property PersistentProperties visibilities
    required property PersistentProperties state
    required property var panels
    required property real maxHeight

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Tab indices for readability
    readonly property int tabText: 0
    readonly property int tabImages: 1
    readonly property int tabTranscriptions: 2

    // Get all cliphist entries (search-filtered if searching, otherwise raw).
    // Transcriptions are NOT in this list — they live in TranscriptionStore
    // and are surfaced separately in `allTranscriptionEntries` below.
    readonly property var allFilteredEntries: {
        // Reactive dependency touch — QML only tracks properties actually read
        // in the expression. The bare read registers the dependency without
        // affecting the return value.
        Clipboard.entries.length;
        if (!searchBar.debouncedText) return Clipboard.entries;

        // Direct FZF/Fuzzysort search on clipboard entries
        const useFuzzy = Config.clipboard.useFuzzy;
        if (useFuzzy) {
            return Fuzzy.go(searchBar.debouncedText, Clipboard.entries, {
                key: "preview", all: true
            }).map(r => r.obj);
        }
        return new Fzf.Finder(Clipboard.entries, {
            selector: e => e.preview
        }).find(searchBar.debouncedText).map(r => r.item);
    }

    // Text tab — every non-image cliphist entry. Transcriptions briefly land
    // in cliphist when delivered via wl-copy, but the SttJob / TranscriptionStore
    // delete-query scrub (~300ms after copy) removes them before the clipboard
    // manager renders, so no client-side exclusion is needed.
    readonly property var allTextEntries: allFilteredEntries.filter(e => !e.isImage)

    // Transcriptions tab — fed directly from the authoritative
    // TranscriptionStore. Each entry is mapped to a ClipboardItem-compatible
    // shape (id, preview, isImage, _kind) so the existing TextList / delegate
    // pipeline can render them without forking. `_kind: "transcription"` tells
    // ClipboardItem to route the click through TranscriptionStore.paste()
    // instead of Clipboard.restore().
    readonly property var allTranscriptionEntries: {
        const items = TranscriptionStore.entries.map(e => ({
            id: e.id,
            preview: e.text,
            addedAt: e.addedAt,
            isImage: false,
            _kind: "transcription"
        }));
        if (!searchBar.debouncedText) return items;

        const useFuzzy = Config.clipboard.useFuzzy;
        if (useFuzzy) {
            return Fuzzy.go(searchBar.debouncedText, items, {
                key: "preview", all: true
            }).map(r => r.obj);
        }
        return new Fzf.Finder(items, {
            selector: e => e.preview
        }).find(searchBar.debouncedText).map(r => r.item);
    }

    // Whether more entries can be loaded for each progressive model
    readonly property bool _hasMoreText: _textModel.count < allTextEntries.length
    readonly property bool _hasMoreTranscriptions: _transcriptionsModel.count < allTranscriptionEntries.length
    readonly property int _pageSize: Config.clipboard.maxDisplayed

    // Progressive ListModels: only hold the currently visible slice.
    // append() adds entries without disturbing existing delegates or scroll position.
    ListModel { id: _textModel }
    ListModel { id: _transcriptionsModel }

    // Sync models when backing data changes (search, new clipboard entries,
    // new STT transcriptions)
    onAllTextEntriesChanged: _resetTextEntries()
    onAllTranscriptionEntriesChanged: _resetTranscriptionEntries()
    // Images use a ListModel from Clipboard — append() adds delegates
    // incrementally without destroying existing ones (progressive loading).
    readonly property var imageEntries: Clipboard.decodedImageEntries

    // Shared image navigation helpers (used by both search and imageNavFocus key handlers)
    function _imageNavUp(): void {
        const imageGrid = imagePane.item;
        if (!imageGrid || root.imageEntries.count === 0) return;
        const cols = imageGrid.columnCount;
        if (imageGrid.currentIndex >= cols)
            imageGrid.currentIndex -= cols;
    }

    function _imageNavDown(): void {
        const imageGrid = imagePane.item;
        if (!imageGrid || root.imageEntries.count === 0) return;
        const cols = imageGrid.columnCount;
        const newIndex = imageGrid.currentIndex + cols;
        if (newIndex < root.imageEntries.count)
            imageGrid.currentIndex = newIndex;
    }

    function _imageNavLeft(): void {
        const imageGrid = imagePane.item;
        if (!imageGrid || root.imageEntries.count === 0) return;
        if (imageGrid.currentIndex > 0)
            imageGrid.currentIndex--;
    }

    function _imageNavRight(): void {
        const imageGrid = imagePane.item;
        if (!imageGrid || root.imageEntries.count === 0) return;
        const newIndex = imageGrid.currentIndex + 1;
        if (newIndex < root.imageEntries.count)
            imageGrid.currentIndex = newIndex;
    }

    function _imageNavConfirm(): void {
        const imageGrid = imagePane.item;
        if (!imageGrid) return;
        const entry = root.imageEntries.get(imageGrid.currentIndex)?.entry;
        if (entry) {
            Clipboard.restore(entry.id);
            root.visibilities.clipboard = false;
        }
    }

    // Incremental sync: adjust the progressive ListModel's count to match
    // `allTextEntries.length` (capped at maxDisplayed) WITHOUT issuing a
    // wholesale clear+append. The model only stores `{idx}` pointers; the
    // delegate resolves content via `entry: root.allEntries[idx]` at render
    // time, so existing delegates pick up new content automatically when
    // the underlying array changes. Avoiding clear+append sidesteps a Qt
    // ListView quirk where overlapping `remove` and `add` transitions can
    // leave stale delegates in the scene (visible as duplicated entries
    // after a new transcription lands while the drawer is open).
    function _resetTextEntries(): void {
        const target = Math.min(Config.clipboard.maxDisplayed, allTextEntries.length);
        _syncProgressiveModel(_textModel, target);
    }

    function _appendTextEntries(count: int): void {
        const start = _textModel.count;
        const end = Math.min(start + count, allTextEntries.length);
        for (let i = start; i < end; i++)
            _textModel.append({ idx: i });
    }

    function _loadMoreText(): void {
        if (!_hasMoreText) return;
        _appendTextEntries(_pageSize);
    }

    function _resetTranscriptionEntries(): void {
        const target = Math.min(Config.clipboard.maxDisplayed, allTranscriptionEntries.length);
        _syncProgressiveModel(_transcriptionsModel, target);
    }

    function _appendTranscriptionEntries(count: int): void {
        const start = _transcriptionsModel.count;
        const end = Math.min(start + count, allTranscriptionEntries.length);
        for (let i = start; i < end; i++)
            _transcriptionsModel.append({ idx: i });
    }

    function _loadMoreTranscriptions(): void {
        if (!_hasMoreTranscriptions) return;
        _appendTranscriptionEntries(_pageSize);
    }

    // Bring `model` to exactly `target` items of shape {idx: i} for i in [0, target).
    // Grows by appending; shrinks by removing the tail. Runs in O(|delta|).
    function _syncProgressiveModel(model: ListModel, target: int): void {
        const current = model.count;
        if (current === target) return;
        if (current < target) {
            for (let i = current; i < target; i++)
                model.append({ idx: i });
        } else {
            while (model.count > target)
                model.remove(model.count - 1);
        }
    }

    // Active-pane helpers — used by the search bar and key handlers so the
    // same controls drive the text or transcriptions list depending on tab.
    readonly property var _activePane: {
        if (root.state.currentTab === root.tabText) return textPane.item;
        if (root.state.currentTab === root.tabTranscriptions) return transcriptionsPane.item;
        return null;
    }
    readonly property var _activeModel: {
        if (root.state.currentTab === root.tabText) return _textModel;
        if (root.state.currentTab === root.tabTranscriptions) return _transcriptionsModel;
        return null;
    }
    readonly property var _activeAllEntries: {
        if (root.state.currentTab === root.tabText) return root.allTextEntries;
        if (root.state.currentTab === root.tabTranscriptions) return root.allTranscriptionEntries;
        return [];
    }
    readonly property bool _activeHasMore: {
        if (root.state.currentTab === root.tabText) return root._hasMoreText;
        if (root.state.currentTab === root.tabTranscriptions) return root._hasMoreTranscriptions;
        return false;
    }
    function _activeLoadMore(): void {
        if (root.state.currentTab === root.tabText) root._loadMoreText();
        else if (root.state.currentTab === root.tabTranscriptions) root._loadMoreTranscriptions();
    }

    // Track if we've incremented refCount to avoid double increment/decrement
    property bool _refCounted: false

    // Focus management: dynamic target based on current tab
    // Search bar receives focus on text-style tabs (Text, Transcriptions);
    // imageNavFocus on the Images tab.
    FocusManager {
        active: root.visibilities.clipboard
        target: root.state.currentTab === root.tabImages ? imageNavFocus : searchBar.focusTarget
        onOpen: () => {
            // Increment ref count on open
            if (!root._refCounted) {
                root._refCounted = true;
                Clipboard.refCount++;
            }
            // Reset models to initial batches and list indices on open
            root._resetTextEntries();
            root._resetTranscriptionEntries();
            if (textPane.item)
                textPane.item.currentIndex = 0;
            if (imagePane.item)
                imagePane.item.currentIndex = 0;
            if (transcriptionsPane.item)
                transcriptionsPane.item.currentIndex = 0;
        }
        onClose: () => {
            // Decrement ref count on close
            if (root._refCounted) {
                root._refCounted = false;
                Clipboard.refCount--;
            }
            // Clear search and reset state
            searchBar.clear();
            // Clear any open image preview so reopening the drawer starts clean
            root.state.previewEntry = null;
        }
    }

    // Handle tab changes to switch focus appropriately
    Connections {
        target: root.state

        function onCurrentTabChanged(): void {
            if (!root.visibilities.clipboard) return;
            if (root.state.currentTab === root.tabImages)
                imageNavFocus.forceActiveFocus();
            else
                searchBar.focusTarget.forceActiveFocus();
        }

        // When the image preview closes (Escape), return focus to the grid so
        // arrow keys / Space work again. ImagePreview.qml grabs focus on open;
        // this handler is the reverse path.
        function onPreviewEntryChanged(): void {
            if (!root.visibilities.clipboard) return;
            if (root.state.previewEntry === null
                && root.state.currentTab === root.tabImages)
                imageNavFocus.forceActiveFocus();
        }
    }

    Component.onDestruction: {
        if (root._refCounted)
            Clipboard.refCount--;
    }

    implicitWidth: Config.clipboard.sizes.itemWidth + padding * 2
    // tabsCard.anchors.topMargin = Appearance.padding.normal  (above the tab strip card)
    // padding * 3            = below-tabs gap + searchBar.anchors.topMargin + bottom margin
    // padding.normal * 4     = internal padding of the two PillCard frames (tabsCard + contentCard, top+bottom each)
    implicitHeight: tabsCard.implicitHeight + tabsCard.anchors.topMargin + contentCard.implicitHeight + searchBar.implicitHeight + padding * 3
    // Note: on Images tab, searchBar collapses to 0 but its anchors.topMargin
    // (root.padding) remains, creating slightly more bottom padding. This is
    // intentional — changing it would break the constant-sum animation invariant.

    // Tab strip card — claymorphism PillCard frame around the Text/Images/
    // Transcriptions cycler. Mirrors `navSection` from Calendar.qml's panelMode
    // path: outer Item hosts the PillCard, inner Tabs is inset by
    // padding.normal so it breathes inside the clay frame.
    Item {
        id: tabsCard

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Appearance.padding.normal
        anchors.leftMargin: Appearance.padding.large
        anchors.rightMargin: Appearance.padding.large

        implicitHeight: tabs.implicitHeight + Appearance.padding.normal * 2

        PillCard {
            anchors.fill: parent
        }

        Tabs {
            id: tabs

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Appearance.padding.normal
            anchors.rightMargin: Appearance.padding.normal

            // Tabs's indicator x-math uses nonAnimWidth as the available tab-row
            // width. tabs.width (post-anchor resolution) exactly matches bar.width
            // and replaces the old pre-computed `root.implicitWidth - margins*2`
            // which was close but included large-padding margins instead of
            // normal-padding margins. Using tabs.width is both simpler and precise.
            nonAnimWidth: tabs.width
            state: root.state
        }
    }

    // Content card — claymorphism PillCard frame around the swipeable panes.
    // The inner ClippingRectangle still owns the swipe clip; the card is the
    // visual frame around it. Mirrors `bodySection` in Calendar.qml.
    Item {
        id: contentCard

        anchors.top: tabsCard.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: contentWrapper.implicitHeight + Appearance.padding.normal * 2

        PillCard {
            anchors.fill: parent
        }

        // Content area with horizontal swipe
        ClippingRectangle {
            id: contentWrapper

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Appearance.padding.normal
            anchors.leftMargin: Appearance.padding.normal
            anchors.rightMargin: Appearance.padding.normal

            height: implicitHeight
            radius: Appearance.rounding.normal
            color: "transparent"

            // Height expands on Images tab to reclaim collapsed search bar space
            implicitHeight: root.state.currentTab === root.tabImages
                ? root.maxHeight / 2 + searchBar.naturalHeight
                : root.maxHeight / 2

            Behavior on implicitHeight {
                Anim {
                    duration: Appearance.anim.durations.large
                    easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                }
            }

            Flickable {
                id: view

                readonly property int currentIndex: root.state.currentTab
                readonly property Item currentItem: row.children[currentIndex]

                anchors.fill: parent

                flickableDirection: Flickable.HorizontalFlick

                contentX: currentItem?.x ?? 0
                contentWidth: row.implicitWidth
                contentHeight: row.implicitHeight

                // Swipe gesture handling
                onContentXChanged: {
                    if (!moving || !currentItem)
                        return;

                    const x = contentX - currentItem.x;
                    if (x > currentItem.implicitWidth / 2)
                        root.state.currentTab = Math.min(root.state.currentTab + 1, tabs.count - 1);
                    else if (x < -currentItem.implicitWidth / 2)
                        root.state.currentTab = Math.max(root.state.currentTab - 1, 0);
                }

                onDragEnded: {
                    if (!currentItem)
                        return;

                    const x = contentX - currentItem.x;
                    if (x > currentItem.implicitWidth / 10)
                        root.state.currentTab = Math.min(root.state.currentTab + 1, tabs.count - 1);
                    else if (x < -currentItem.implicitWidth / 10)
                        root.state.currentTab = Math.max(root.state.currentTab - 1, 0);
                    else
                        contentX = Qt.binding(() => currentItem?.x ?? 0);
                }

                RowLayout {
                    id: row

                    spacing: 0

                    // Text tab pane
                    Pane {
                        id: textPane
                        index: 0
                        sourceComponent: TextList {
                            entries: _textModel
                            allEntries: root.allTextEntries
                            hasMore: root._hasMoreText
                            loadMore: () => root._loadMoreText()
                            visibilities: root.visibilities
                            searchQuery: searchBar.debouncedText
                            maxHeight: contentWrapper.implicitHeight
                        }
                    }

                    // Images tab pane
                    Pane {
                        id: imagePane
                        index: 1
                        sourceComponent: ImageGrid {
                            entries: root.imageEntries
                            visibilities: root.visibilities
                            searchQuery: ""  // Images don't support search
                            maxHeight: contentWrapper.implicitHeight
                        }
                    }

                    // Transcriptions tab pane — reuses TextList with the
                    // transcriptions-only model.
                    Pane {
                        id: transcriptionsPane
                        index: 2
                        sourceComponent: TextList {
                            entries: _transcriptionsModel
                            allEntries: root.allTranscriptionEntries
                            hasMore: root._hasMoreTranscriptions
                            loadMore: () => root._loadMoreTranscriptions()
                            visibilities: root.visibilities
                            searchQuery: searchBar.debouncedText
                            maxHeight: contentWrapper.implicitHeight
                        }
                    }
                }

                Behavior on contentX {
                    Anim {}
                }
            }
        }
    }

    // Search bar at bottom — collapses on Images tab.
    // Drives whichever text-style pane (Text or Transcriptions) is active.
    ClipboardSearchBar {
        id: searchBar

        isTextTab: root.state.currentTab !== root.tabImages
        entryCount: root.state.currentTab === root.tabTranscriptions
            ? root.allTranscriptionEntries.length
            : root.allTextEntries.length
        padding: root.padding
        confirmTimeout: Config.clipboard.clearConfirmTimeout

        // Anchors to contentCard (the new outer card wrapper), not to
        // contentWrapper directly — QML anchors must reference siblings or the
        // parent, and contentWrapper now lives nested inside contentCard.
        anchors.top: contentCard.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        onAccepted: {
            const list = root._activePane;
            if (!list) return;
            const model = root._activeModel;
            const idx = model?.get(list.currentIndex)?.idx;
            const entry = idx !== undefined ? root._activeAllEntries[idx] : undefined;
            if (entry) {
                if (entry._kind === "transcription")
                    TranscriptionStore.paste(entry.id);
                else
                    Clipboard.restore(entry.id);
                root.visibilities.clipboard = false;
            }
        }

        onNavigateUp: {
            const list = root._activePane;
            if (!list) return;
            if (list.currentIndex > 0)
                list.currentIndex--;
        }

        onNavigateDown: {
            const list = root._activePane;
            if (!list) return;
            const model = root._activeModel;
            if (list.currentIndex < (model?.count ?? 0) - 1) {
                list.currentIndex++;
            } else if (root._activeHasMore) {
                root._activeLoadMore();
            }
        }

        onRequestClose: root.visibilities.clipboard = false
        onRequestTabCycle: root.state.currentTab = (root.state.currentTab + 1) % tabs.count
        onClearAllRequested: Clipboard.clear()
    }

    // Invisible focus receiver for images tab keyboard navigation.
    // Lives outside searchBar (which collapses on Images tab) so it
    // remains visible and focusable for keyboard nav on the Images tab.
    Item {
        id: imageNavFocus

        width: 0
        height: 0
        visible: root.state.currentTab === root.tabImages

        Keys.onUpPressed: root._imageNavUp()
        Keys.onDownPressed: root._imageNavDown()
        Keys.onLeftPressed: root._imageNavLeft()
        Keys.onRightPressed: root._imageNavRight()

        Keys.onReturnPressed: root._imageNavConfirm()

        Keys.onEscapePressed: root.visibilities.clipboard = false

        // Space opens a maximized preview of the currently selected image.
        // The preview overlay lives in modules/drawers/Panels.qml and reads
        // root.state.previewEntry; setting it triggers the open animation
        // and shifts keyboard focus to the overlay.
        Keys.onSpacePressed: event => {
            if (root.imageEntries.count === 0 || imagePane.item === null) {
                event.accepted = true;
                return;
            }
            const entry = root.imageEntries.get(imagePane.item.currentIndex)?.entry;
            if (entry)
                root.state.previewEntry = entry;
            event.accepted = true;
        }

        Keys.onPressed: event => {
            // Tab key cycles between tabs
            if (event.key === Qt.Key_Tab) {
                root.state.currentTab = (root.state.currentTab + 1) % tabs.count;
                event.accepted = true;
            }
        }
    }

    Behavior on implicitWidth {
        enabled: root.visibilities.clipboard

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    Behavior on implicitHeight {
        enabled: root.visibilities.clipboard

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    component Pane: Loader {
        required property int index
        Layout.alignment: Qt.AlignTop

        Component.onCompleted: active = Qt.binding(() => {
            return Math.abs(index - view.currentIndex) <= 1;
        })
    }
}
