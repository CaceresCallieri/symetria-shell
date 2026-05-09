pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects

/// Maximized clipboard image preview. Mounted as a sibling of the clipboard
/// drawer inside modules/drawers/Panels.qml so it can fill the entire area
/// between the bar and agentBar without escaping the drawer's bounds.
///
/// Open: clipboard.clipState.previewEntry = entry (e.g. via Space on images tab)
/// Close: clipboard.clipState.previewEntry = null (Escape inside the preview)
///
/// The grid's cached `entry.imagePath` is a 512×512 thumbnail (see
/// scripts/cliphist-decode-image.sh) — too soft for a maximized view. We
/// re-decode the original PNG on-demand into `${Paths.clipboardcache}/full/`
/// and crossfade it over the thumbnail when ready. The thumbnail provides
/// the immediate scale-up animation visual; the full-res replaces it as soon
/// as `cliphist decode` finishes.
Item {
    id: root

    /// The clipboard's clipState PersistentProperties — drives the preview
    /// state and is mutated to close the preview.
    required property PersistentProperties clipState

    readonly property var previewEntry: clipState?.previewEntry ?? null
    readonly property bool isOpen: previewEntry !== null
    // Raw filesystem path — used to build the file:// URL for Image.source.
    // Kept as string because it mirrors entry.imagePath (string in Clipboard service)
    // and feeds a template literal rather than being assigned to source directly.
    readonly property string imagePath: previewEntry?.imagePath ?? ""

    // Full-resolution cache lives under the existing clipboard cache dir. That
    // dir is wiped on every Clipboard.refresh() (drawer open), so full-res
    // blobs are effectively per-session and need no extra cleanup hook.
    readonly property string _fullCacheDir: `${Paths.clipboardcache}/full`

    // Set by the decode Process once the full-res file is ready. Empty until
    // then, which keeps `fullImage` invisible and the thumbnail showing through.
    // Declared as url so Image.source receives a proper QUrl directly (no runtime
    // QUrl construction on every binding evaluation).
    property url fullImagePath: ""

    // Render gating decoupled from `isOpen`:
    //   • On open  — flip `_renderOpen` true synchronously so root snaps to
    //     full size in a single frame. Children then animate scale/opacity
    //     from a fully-sized parent, which keeps `imageHolder`'s default
    //     `transformOrigin: Item.Center` honest (the visual grows from the
    //     middle of the screen, not from the top-left).
    //   • On close — keep `_renderOpen` true for one animation duration so
    //     scrim fade / imageHolder scale-down can play, then collapse the
    //     geometry to 0×0 so the drawer window's XOR mask stops subtracting
    //     this region (otherwise the inter-bar area would stay click-capture).
    //
    // Why not animate width/height directly: with anchors at top-left, an
    // animated 0→full width grows rightward from x=0 (and 0→full height
    // grows downward from y=0). That made the entire overlay appear to pour
    // out of the top-left corner, even though `imageHolder.scale` was
    // centered. Snapping size + animating only the children fixes that.
    property bool _renderOpen: false

    Timer {
        id: closeTimer
        interval: Appearance.anim.durations.large
        onTriggered: root._renderOpen = false
    }

    onIsOpenChanged: {
        if (isOpen) {
            closeTimer.stop();
            _renderOpen = true;
        } else {
            // Defer the geometry collapse so child animations can finish.
            closeTimer.restart();
        }
    }

    width: _renderOpen ? parent.width : 0
    height: _renderOpen ? parent.height : 0
    visible: _renderOpen

    // Drive focus + decode on every previewEntry change. Both open (null →
    // entry) and same-session entry switches go through here; the close edge
    // (entry → null) just clears the cached full-res path. The reverse focus
    // path (back to the grid on close) is handled by Content.qml's Connections.
    //
    // Why not use `onIsOpenChanged`: previewEntry changing also flips isOpen,
    // so wiring both would double-fire the decode at open time.
    onPreviewEntryChanged: {
        if (previewEntry === null) {
            // Drop the full-res reference so the next open starts from the
            // thumbnail and we don't briefly flash the prior entry's image.
            fullImagePath = "";
            return;
        }
        focusReceiver.forceActiveFocus();
        _requestFullDecode();
    }

    function _requestFullDecode(): void {
        if (!previewEntry)
            return;
        const id = previewEntry.id;
        const out = `${_fullCacheDir}/${id}.png`;
        // Hold off on flipping fullImagePath until the file actually exists —
        // setting it now would cause the Image element to fail-load and not
        // retry once the decode finishes.
        fullDecoder.entryId = id;
        fullDecoder.outputPath = out;
        fullDecoder.command = [
            "bash", "-c",
            // mkdir -p the cache; only re-decode when the file is missing so
            // re-previewing the same entry within a session is instant.
            'mkdir -p "$(dirname "$2")" && { [ -f "$2" ] || cliphist decode "$1" > "$2"; }',
            "cliphist-decode-full",
            id,
            out
        ];
        // Kill any in-flight decode before starting a new one. QuickShell's
        // Process silently ignores running=true while already running
        // (startProcessIfReady() returns early when this->process != nullptr),
        // so rapid entry switches would otherwise leave the new entry undecoded.
        fullDecoder.running = false;
        fullDecoder.running = true;
    }

    Process {
        id: fullDecoder

        property string entryId
        property string outputPath

        running: false

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(`[ClipboardPreview] full decode ${entryId} failed exit=${exitCode}`);
                return;
            }
            // Race guard: the user may have closed the preview or moved to a
            // different entry while the decode was running. Only publish the
            // path if it still corresponds to what's on screen.
            if (root.previewEntry?.id !== entryId)
                return;
            root.fullImagePath = Qt.url(`file://${outputPath}`);
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn(`[ClipboardPreview] decode stderr: ${text.trim()}`);
            }
        }
    }

    // Backdrop scrim — dims the panels-level area without touching the bars.
    // Opacity is intentionally low so the underlying Hyprland window stays
    // clearly readable behind the focal image; the user wants context, not a
    // blackout. Corner radius matches Config.border.rounding so the scrim
    // tucks behind the shell's existing rounded inner edges (left corners are
    // rounded by modules/drawers/Border.qml; matching all four keeps the
    // overlay visually coherent with the rest of the shell).
    StyledRect {
        anchors.fill: parent
        color: Colours.palette.m3scrim
        radius: Config.border.rounding
        opacity: root.isOpen ? 0.4 : 0

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.large
                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
            }
        }
    }

    // Catch clicks anywhere on the scrim so they don't fall through to other
    // panel children. Clicking dismisses the preview as a UX bonus.
    MouseArea {
        anchors.fill: parent
        enabled: root.isOpen
        onClicked: root.clipState.previewEntry = null
    }

    // Container with the geometry used by both Image layers. Kept as a single
    // Item so `scale` animates the thumbnail and full-res in lockstep.
    Item {
        id: imageHolder

        anchors.fill: parent
        anchors.margins: Appearance.padding.large * 2

        scale: root.isOpen ? 1.0 : 0.85
        opacity: root.isOpen ? 1.0 : 0

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.large
                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
            }
        }

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.large
                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
            }
        }

        // Soft drop shadow lifts the image off the scrim. Applied at the
        // holder level so it matches whichever layer is currently visible.
        layer.enabled: root.isOpen
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1.0
            shadowVerticalOffset: 8
            shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.6)
        }

        // Thumbnail layer — instantly visible during the open animation. Stays
        // visible underneath as the full-res fades in (and as a fallback if
        // the full-res decode fails or is slow).
        Image {
            id: thumbnailImage

            anchors.fill: parent
            source: root.imagePath ? `file://${root.imagePath}` : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            cache: true
            // Thumbnail is produced at 512×512 by cliphist-decode-image.sh —
            // cap GPU-side decode to that size so no memory is wasted scaling
            // up to the display rect.
            sourceSize.width: 512
            sourceSize.height: 512
        }

        // Full-resolution layer — fades in once `cliphist decode` finishes
        // writing the file. PreserveAspectFit + identical anchors to
        // thumbnailImage means the rendered rect matches pixel-for-pixel,
        // so the crossfade has no perceptible shift.
        Image {
            id: fullImage

            anchors.fill: parent
            source: root.fullImagePath
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            cache: true

            // Don't set sourceSize — the whole point is full resolution. The
            // Image element scales its rendered output to the display rect at
            // draw time (mipmap smoothing handles the downscale).

            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity {
                Anim {
                    duration: Appearance.anim.durations.normal
                }
            }
        }
    }

    // Invisible focus receiver — owns Escape while the preview is open.
    Item {
        id: focusReceiver

        anchors.fill: parent
        focus: root.isOpen

        Keys.onEscapePressed: root.clipState.previewEntry = null
        // Space toggles the preview shut too, matching the open gesture.
        Keys.onSpacePressed: root.clipState.previewEntry = null
    }
}
