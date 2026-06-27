pragma Singleton

import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick
import Symmetria

/// Video trimmer service — drives the in-shell quick-trim panel.
///
/// Opened via the `videoTrim` IPC target (see bottom): `editLast` resolves the
/// newest screen recording and `open <path>` targets a specific file (used by
/// the CLI's "Trim" notification action). The actual cut is a stream-copy
/// ffmpeg call — NO re-encode — so it finishes in well under a second:
///
///   ffmpeg -ss <in> -i <src> -t <dur> -c copy <src>_trimmed.mp4
///
/// Because `-c copy` cuts on the nearest keyframe (gpu-screen-recorder's
/// default interval is ~2s, no override in shell.json), the in-point can land
/// up to ~2s off. That's intentional: the purpose is shaving dead air so an
/// agent ingests the clip faster, not frame-accurate editing — paying the cost
/// of a re-encode for precision we don't need would defeat the "quick" goal.
///
/// Output is non-destructive: the trimmed file is written alongside the
/// original as `<stem>_trimmed.mp4`, the original is kept, and the trimmed
/// path is copied to the clipboard for hand-off to an agent.
Singleton {
    id: root

    /// Absolute path of the recording currently loaded for trimming ("" = none).
    property string source: ""

    /// file:// URL form of `source`, for MediaPlayer.
    readonly property string sourceUrl: source.length > 0 ? "file://" + source : ""

    /// Basename of `source`, for the panel title.
    readonly property string sourceName: {
        const slash = source.lastIndexOf("/");
        return slash >= 0 ? source.substring(slash + 1) : source;
    }

    /// Whether the trim panel should be shown.
    property bool visible: false

    /// Monitor name the panel is bound to — captured at open time so the
    /// scrubber (and its single MediaPlayer) appears only on the focused
    /// screen, not duplicated across every monitor's drawer. Mirrors the
    /// targetMonitor capture in KeyChordsService.
    property string targetScreen: ""

    /// True while ffmpeg is running — the Content view disables the Trim button.
    property bool trimming: false

    /// Directory holding the extracted filmstrip thumbnails for the current
    /// source. Stable path under the runtime dir (per-user, tmpfs-backed) —
    /// cleared and regenerated on each generateThumbnails() call.
    readonly property string thumbnailDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/symmetria-videotrim`

    /// Bumped each time a thumbnail batch finishes. The Content addresses frames
    /// by deterministic path carrying a `?v=thumbnailVersion` query, so changing
    /// this value busts Qt's image cache and forces the (externally written)
    /// frames to reload — chosen over FolderListModel, which does not reliably
    /// surface externally-written, mid-session-regenerated files.
    property int thumbnailVersion: 0

    /// Extract `count` evenly-spaced filmstrip thumbnails from `source` into
    /// thumbnailDir. fps=count/duration yields ~count frames across the clip;
    /// scaled to 96px tall and cropped to a consistent cell by the view.
    function generateThumbnails(durationSec: real, count: int): void {
        if (source.length === 0 || durationSec <= 0 || count <= 0)
            return;
        const rate = count / durationSec;
        // Single-quote for the shell, escaping any embedded quote (' -> '\'') so
        // a path arriving via the public open() IPC can't break out of quoting.
        const shq = s => "'" + s.replace(/'/g, "'\\''") + "'";
        const dir = shq(thumbnailDir);
        const src = shq(source);
        thumbProc.command = ["sh", "-c",
            `rm -rf ${dir} && mkdir -p ${dir} && ` +
            `ffmpeg -y -i ${src} -vf "fps=${rate},scale=-1:96" ` +
            `-frames:v ${count} ${dir}/thumb_%03d.jpg >/dev/null 2>&1`];
        thumbProc.running = true;
    }

    /// Open the trimmer on an explicit recording path (notification "Trim" action).
    function open(path: string): void {
        if (!path || path.length === 0) {
            Toaster.toast(qsTr("Nothing to trim"), qsTr("No recording path was provided"), "error", Toast.Error);
            return;
        }
        source = path;
        targetScreen = Hypr.focusedMonitor?.name ?? "";
        visible = true;
    }

    /// Open the trimmer on the most recent screen recording (keychord path).
    function editLast(): void {
        findLast.running = true;
    }

    /// Dismiss the panel without trimming.
    function close(): void {
        visible = false;
        source = "";
        targetScreen = "";
    }

    // Resolve the newest ORIGINAL recording for editLast — excludes
    // *_trimmed.mp4 outputs so "edit last" always targets the source clip, not
    // a clip we just produced (which would compound the suffix on re-trim).

    /// Trim `source` to [inSec, outSec] via stream-copy ffmpeg. Non-destructive:
    /// writes `<stem>_trimmed.mp4`, then copies that path to the clipboard.
    function trim(inSec: real, outSec: real): void {
        if (trimming || source.length === 0)
            return;
        const dur = Math.max(0.1, outSec - inSec);
        const dot = source.lastIndexOf(".");
        let stem = dot > 0 ? source.substring(0, dot) : source;
        // Collapse any existing _trimmed suffix so re-trimming a trimmed clip
        // yields <original>_trimmed.mp4, never <...>_trimmed_trimmed.mp4.
        if (stem.endsWith("_trimmed"))
            stem = stem.substring(0, stem.length - "_trimmed".length);
        const out = stem + "_trimmed.mp4";

        // -ss before -i: fast keyframe seek (accurate enough, see header note).
        // -avoid_negative_ts make_zero: rebase timestamps so the copied stream
        // starts cleanly at 0 instead of carrying the source's keyframe offset.
        trimProc.outPath = out;
        // Snapshot the source so the (async) exit handler only dismisses the
        // panel if the user hasn't opened a different clip in the meantime.
        trimProc.trimmedSource = source;
        trimProc.command = [
            "ffmpeg", "-y",
            "-ss", inSec.toFixed(3),
            "-i", source,
            "-t", dur.toFixed(3),
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            out
        ];
        trimming = true;
        trimProc.running = true;
    }

    // Resolve the newest recording_*.mp4 for editLast(). ls -1t sorts by mtime
    // (newest first); head takes the first. Empty output → no recordings.
    Process {
        id: findLast

        command: ["sh", "-c", `ls -1t "${Paths.recsdir}"/recording_*.mp4 2>/dev/null | grep -v '_trimmed\\.mp4$' | head -n1`]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length === 0)
                    Toaster.toast(qsTr("Nothing to trim"), qsTr("No recordings found"), "error", Toast.Error);
                else
                    root.open(p);
            }
        }
    }

    // Filmstrip extractor. On success bumps thumbnailVersion, whose value the
    // Content's frame URLs carry as a ?v= cache-bust so the new (externally
    // written) frames reload. See the thumbnailVersion property.
    Process {
        id: thumbProc

        onExited: (code, status) => {
            // Only signal a fresh batch on success — a failed ffmpeg leaves no
            // new frames, so bumping would force reloads against missing files.
            if (code === 0)
                root.thumbnailVersion++;
        }
    }

    Process {
        id: trimProc

        property string outPath: ""
        // Source captured at trim start; see trim() and the close guard below.
        property string trimmedSource: ""

        onExited: (code, status) => {
            root.trimming = false;
            if (code === 0) {
                Quickshell.execDetached(["wl-copy", outPath]);
                Toaster.toast(qsTr("Recording trimmed"), qsTr("Saved and path copied to clipboard"), "content_cut", Toast.Success);
                // Don't dismiss a session the user has since re-pointed at a
                // different clip while this trim was running.
                if (root.source === trimProc.trimmedSource)
                    root.close();
            } else {
                Toaster.toast(qsTr("Trim failed"), qsTr("ffmpeg exited with code %1").arg(code), "error", Toast.Error);
            }
        }
    }

    // IPC surface for the trimmer. `open` takes the recording path from the
    // CLI's "Trim" notification action; `editLast` is bound to the recording
    // keychord menu's "e" entry. Target is "videoTrim" to avoid collision with
    // the "recorder" (audio/STT) and "screenRecorder" (capture) IPC targets.
    IpcHandler {
        target: "videoTrim"

        function editLast(): void {
            root.editLast();
        }

        function open(path: string): void {
            root.open(path);
        }
    }
}
