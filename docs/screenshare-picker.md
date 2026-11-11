# Native screen-sharing picker

The XDPH custom picker runs `scripts/screenshare_picker.py`. The adapter reads
XDPH's issued sources, captures screen snapshots before the layer maps, and
opens the `screenshare` IPC target in the existing Symmetria process. It never
starts a shell or changes a Hyprland window rule.

`modules/screenshare` draws the picker on `WlrLayer.Overlay`. The layer uses
exclusive keyboard focus only while its request is active. The dialog occupies
90% of the requesting window, bounded by the monitor work area. `PillCard`,
`PillSurface`, `StyledText`, `StyledSwitch`, `Colours`, and `Appearance` provide
the shared design system. No HTML, Electron process, embedded palette, or
separate icon set is needed.

## Request lifetime

Each adapter creates a private directory in `XDG_RUNTIME_DIR`, a mode-0600 Unix
socket, and a random token. The shell connects to that request socket after IPC
validates its path. The adapter verifies the peer UID and the token on replies.
The adapter validates the final selection against the sources XDPH issued.
Window/workspace identifiers remain strings. Workspace lengths count UTF-8 bytes.
Regions use output-local logical coordinates with positive half-up rounding.

Confirm writes one `[SELECTION]` line to the adapter's stdout. Cancel and a lost
shell connection write no selection. Disconnecting clears the shell state and
unmaps the layer. Concurrent requests receive `busy` instead of replacing an
existing consent request. Temporary snapshots disappear when the adapter exits.
Window previews load through a pool of three captures. Missing snapshots retain
the source icon and title instead of inventing a preview.

Frontend cancellation and adapter disconnection are separate boundaries. XDPH
1.5.0 waits synchronously for its custom picker during `SelectSources`. Its
session-close handler does not stop that picker process. Closing the requesting
application or timing out a manual test can therefore leave the picker open.
Escape or the close control cancels that picker and releases its connection.
Do not report frontend-cancellation cleanup as covered by socket-disconnect tests.
The upstream implementations are:

- https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/v1.5.0/src/portals/Screencopy.cpp
- https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/v1.5.0/src/helpers/MiscFunctions.cpp

## Activation and migration

The shell must load the new QML module before the portal can use it. Restart the
shell only with the operator's explicit authorization. Then enable the adapter:

```sh
python3 ~/.config/quickshell/symmetria/scripts/configure-screenshare-picker.py enable
```

The manager checks the live `screenshare status` IPC target before writing.
It refuses activation while that target is absent or busy. It also refuses an
active portal video source, config symlinks, existing unmanaged custom pickers,
and later user edits to the owned config. Both enable and disable restart only
`xdg-desktop-portal-hyprland`. They do not restart Symmetria.

The manager can migrate the installed Electron prototype by replacing its owned
picker command. It preserves the original backup in the existing activation
record under the desktop user's XDG data directory. The record remains state,
not a second source tree. The manager restores config bytes and permissions if
the write or service restart fails. The workspace's XDG overrides do not determine
the desktop paths.

```sh
python3 ~/.config/quickshell/symmetria/scripts/configure-screenshare-picker.py status
python3 ~/.config/quickshell/symmetria/scripts/configure-screenshare-picker.py disable
```

`disable` restores the config from before the original experiment, including its
absence if no config existed. It does not silently revert to the Electron picker.
The old installed runtime is not loaded by the native picker. It can remain as
a migration backup until the operator accepts native compositor behavior.

## Keyboard controls

- Tab / Shift+Tab cycles windows, screens, workspaces, and region from any control.
- 1–4 chooses a mode. Vim keys and arrows follow the current grid columns.
- `/` opens search. Search protects ordinary typed characters. Escape leaves search.
- F6 / Shift+F6 reaches controls, including the output chooser and reset in region mode.
- Enter confirms a source or activates the focused control. `r` toggles remembering.
- Arrows / hjkl moves a region. Shift + direction resizes it. Delete clears it.
- `?` traps focus in shortcut help and returns focus to its invoking control.
- Escape / `q` cancels outside search. The close control uses the small red circle.

## Verification boundary

```sh
python3 -m pytest scripts/tests -q
```

The suite runs actual adapter CLI processes with isolated fake desktop commands
and a socket client. It covers all selection modes, invalid sources, cancellation,
lost connections, token rejection, cleanup, activation, restoration, and rollback.
Qt6 `qmltestrunner` runs the production keyboard controller, selection model, and
region preview with `-platform offscreen`. It tests focus, search isolation, Tab
from controls, confirmation, geometry, and landscape/portrait/ultrawide fitting.
The production header and centered button row also run offscreen. Geometry
checks cover narrow and wide controls, icon visibility, larger heading fonts,
the close control's right edge, and the icon/label group's center and bounds.
Missing `qmltestrunner` skips that check with a named tooling reason.

These checks do not launch Symmetria or prove compositor focus/layer behavior.
That boundary requires the operator-authorized shell restart and an actual share
request. The previous Electron prototype's video-delivery evidence does not prove
the new native boundary. Dependencies remain Python 3, Quickshell, Hyprland, grim,
and XDPH 1.5.0; Node.js and Electron are unnecessary at runtime.
