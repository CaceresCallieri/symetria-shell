# Tray Icon Theming

How Symmetria resolves system tray icons, why Electron apps don't theme
automatically, and what a future "fully automatic" solution would require.

## Goal

Make system tray icons match workspace client icons visually. Both should
render through the active Freedesktop icon theme (e.g. `Symmetria` →
`MacTahoe-grey-dark`) instead of using each app's self-provided pixmap.

## Current pipeline (`utils/Icons.qml`)

`getTrayIcon(id, title, icon)` is called by `modules/bar/components/TrayItem.qml`
with three strings sourced from the StatusNotifierItem D-Bus protocol:

- `id` — the app's advertised SNI id string (e.g. `"steam"`, `"discord"`,
  `"chrome_status_icon_1"`, or a random slug)
- `title` — the SNI `Title`, used only to match `iconSubs` entries
- `icon` — either a theme icon name, an absolute pixmap file path, a
  `name?path=...` SNI pixmap encoding, or a `data:` URI

Resolution order:

1. **User override** — `Config.bar.tray.iconSubs[]` matches on `id` or `title` (`traySubFor`)
2. **Theme by id** — `Quickshell.iconPath(id, true)` against the active theme
3. **DesktopEntries by id** — `DesktopEntries.heuristicLookup(id).icon` →
   `Quickshell.iconPath(entry.icon, true)`
4. **Theme by icon name** — if `icon` is a plain name (not path/URL/data/pixmap),
   try `Quickshell.iconPath(icon, true)` directly
5. **Path heuristic** — if `icon` is an absolute file path, scan its directory
   segments for app-identifying names and try each against the theme
   (`guessThemeNameFromPath`)
6. **Fallback** — parse `?path=` pixmap encoding, otherwise return the raw
   app-provided icon URL

Steps 2-5 run inside `resolveThemedTrayIcon()`. Each returns early on first
hit; empty string means "no themed icon found, fall through to the raw
pixmap."

## Path heuristic details

`guessThemeNameFromPath(path)` filters out generic directory segments
(`tmp`, `opt`, `usr`, `share`, `assets`, `img`, `icons`, `data`,
`flutter_assets`, etc.) and tries the remaining path parts as theme icon
names. File extensions (`.png`, `.svg`, `.jpg`, `.ico`, `.xpm`) are stripped,
and mixed-case segments are retried in lowercase.

Example traces:

| Input path | Filtered candidates | Result |
|------------|---------------------|--------|
| `/opt/localsend/data/flutter_assets/assets/img/logo-32-white.png` | `localsend`, `logo-32-white` | `iconPath("localsend")` → hit |
| `/tmp/qs-a1b2c3/icon.png` | `qs-a1b2c3` | miss (correctly falls through) |
| `/usr/share/icons/hicolor/256x256/apps/foo.png` | `hicolor`, `256x256`, `apps`, `foo` | `iconPath("foo")` if themed, else fallthrough |

## The Electron / Chromium problem

Discord, Heroic Games Launcher, Altus, and every other Electron-based app
registers with SNI using Chromium's generic tray code. At the D-Bus level
(verified via `busctl --user` + `gdbus`):

| App | SNI Id | Title | Tooltip | IconName |
|-----|--------|-------|---------|----------|
| Discord | `chrome_status_icon_1` | *(empty)* | *(empty)* | *(pixmap bytes)* |
| Heroic | `chrome_status_icon_1` | *(empty)* | *(empty)* | *(pixmap bytes)* |
| Altus | `chrome_status_icon_1` | *(empty)* | *(empty)* | *(pixmap bytes)* |

**Update, 2026-10-12:** current Discord no longer matches this table. Its
item reports SNI id `discord_status_icon_1` and the tooltip title
`Discord`, so an `id` override reaches it alone. Heroic and Altus were not
re-checked. The table below records the older Electron behaviour, which an
app on an older Electron still shows.

**All three Electron apps are indistinguishable from each other** at the
QML layer. They share an identical SNI id, carry no title or tooltip,
and ship their tray icon as embedded pixmap bytes via the SNI
`IconPixmap` property (not a file path). Quickshell caches those bytes
to a randomly-named `/tmp/qs-xxxxx/icon.png`, so the path heuristic can't
recover the source app either.

Steps 2-5 of `resolveThemedTrayIcon()` all miss for Electron apps. They
fall through to step 6 and render the raw pixmap — exactly what we were
trying to avoid.

### Why we can't fix this in QML alone

Quickshell's `SystemTrayItem` exposes only 5 string properties:
`id`, `title`, `tooltipTitle`, `tooltipDescription`, `icon`. There is
no `bus`, `pid`, `service`, or `owner` property. From QML we cannot
determine which D-Bus connection owns each tray item, so we can't map
it back to a process or executable.

This is an **upstream Chromium bug** that affects every status-bar
implementation on Linux (KDE, GNOME extensions, Polybar tray, Waybar,
etc.) — not something Symmetria can solve cleanly from its side.

## Workarounds users can apply today

### A. Manual `iconSubs` override

Each entry matches a tray item on its SNI `id`, or on its `title` for an
app that generates its id per session (LocalSend: a random id every
launch, title `org.localsend.localsend_app`). It then replaces the icon
with one of:

- `glyph` — a name the shell's glyph fonts cover (`assets/glyphs`, e.g.
  `brand_discord`). Drawn by `TrayItem` as a shell glyph in the status
  pill's tone, so the tray matches the hairline status glyphs. Falls back
  to the app's own icon while the active glyph family lacks the name
  (`Theme.glyphs` set to `material`). Brand marks are added to
  `assets/glyphs/glyph-map.json` as `brand_*` keys.
- `icon` — an icon-theme name.
- `image` — a file path.

The shipped `config/shell.json` carries glyph entries for Discord, Steam
and LocalSend. The theme-name form looks like this:

```json
{
  "bar": {
    "tray": {
      "iconSubs": [
        { "id": "chrome_status_icon_1", "icon": "discord" }
      ]
    }
  }
}
```

Caveat: an app on an older Electron shares `chrome_status_icon_1`, and
this override forces the same icon on every such tray app. Only useful
if one Electron app is dominant (or the others are rarely visible).

The `image` field accepts an absolute path if you want a custom file
instead of a theme lookup:

```json
{ "id": "chrome_status_icon_1", "image": "/home/me/Pictures/discord.svg" }
```

### B. Install a custom icon into the theme

Drop an SVG at
`~/.local/share/icons/Symmetria/apps/scalable/<name>.svg` and the
Symmetria theme will pick it up (after `gtk-update-icon-cache`). Works
well for one-off apps whose `id` or path segment matches the file name.

## Option C — future "fully automatic" path

To theme Electron apps without user configuration, we would need to
identify the source process. One implementable approach:

1. In `Tray.qml`, when a tray item's bus name becomes available (requires
   Quickshell to expose it — currently blocked), spawn a short-lived
   `busctl --user call org.freedesktop.DBus /org/freedesktop/DBus
   org.freedesktop.DBus.GetConnectionUnixProcessID s <busname>` via
   `Quickshell.Io.Process`.
2. Read `/proc/<pid>/exe` or `/proc/<pid>/comm` to get the executable name.
3. Map common executables to theme icons (e.g. `/opt/discord/Discord` →
   `discord`, `/opt/Heroic/heroic` → `heroic`, `electron*` with inspection
   of `/proc/<pid>/cmdline` to disambiguate wrappers like Altus).
4. Cache results keyed on the bus name to avoid re-spawning processes per
   render frame.

### Why it isn't implemented

- **Requires Quickshell API extension.** `SystemTrayItem` doesn't expose
  the bus name today. Either contribute the property upstream or link
  against Quickshell's internal C++ types via the Symmetria plugin.
- **Process spawning at tray-render time.** Even if cached, the first
  resolution per tray item adds an IPC round-trip. Race conditions are
  possible if the app exits between registration and query.
- **Electron wrapper ambiguity.** Altus is `/usr/lib/electron35/electron`,
  not `/opt/altus/altus`. Distinguishing wrapped apps requires parsing
  `cmdline` for the actual app being launched, which is fragile.
- **Complexity vs. benefit.** Option A + B cover most real cases for a
  single user's setup. Option C is worth it only if many users need it or
  the tradeoffs change (e.g. Quickshell exposes `bus` natively).

If/when Quickshell surfaces a per-item bus name property, revisit this
doc. The heuristic (PID → executable → icon name) is the right shape;
the only blocker is the missing identifier at the QML layer.

## Related files

- `utils/Icons.qml` — `getTrayIcon()`, `resolveThemedTrayIcon()`,
  `guessThemeNameFromPath()`, `pathNoiseSegments`
- `modules/bar/components/TrayItem.qml` — call site
- `config/BarConfig.qml` — `iconSubs` schema
