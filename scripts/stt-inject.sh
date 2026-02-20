#!/bin/sh
# Best-effort paste injection for Symmetria STT
# Pastes clipboard content into the target window via hyprctl sendshortcut.
# Assumes clipboard already contains the transcription (wl-copy ran first).
#
# Usage: stt-inject.sh <window_address> <window_class>
#   window_address: Hyprland window address (e.g., "0x5a3b2c1d")
#   window_class:   Window class string (e.g., "ghostty", "firefox")
#
# Always exits 0 — injection failure is non-fatal (clipboard still has text).

ADDRESS="$1"
WINDOW_CLASS="$2"

# Validate arguments (class is optional — defaults to Ctrl+V if empty)
if [ -z "$ADDRESS" ]; then
    echo "[stt-inject] Missing window address" >&2
    exit 0
fi

# Verify target window still exists
if ! hyprctl clients -j 2>/dev/null | grep -qF "\"address\": \"$ADDRESS\""; then
    echo "[stt-inject] Target window $ADDRESS no longer exists, skipping injection" >&2
    exit 0
fi

# Determine paste shortcut based on window class.
# Terminal emulators use Ctrl+Shift+V; everything else uses Ctrl+V.
CLASS_LOWER=$(echo "$WINDOW_CLASS" | tr '[:upper:]' '[:lower:]')
case "$CLASS_LOWER" in
    *ghostty*|*warp*|*wezterm*|*alacritty*|*kitty*|*foot*|*konsole*|xterm*|urxvt*|*termite*|*sakura*|*tilix*|*terminator*|st-*)
        SHORTCUT="CTRL SHIFT, V"
        ;;
    *)
        SHORTCUT="CTRL, V"
        ;;
esac

# 50ms: allows wl-copy to propagate clipboard to Wayland compositor before sendshortcut reads it
sleep 0.05

# Send paste shortcut to the target window without changing focus
if ! hyprctl dispatch sendshortcut "$SHORTCUT, address:$ADDRESS" 2>/dev/null; then
    echo "[stt-inject] sendshortcut failed for $ADDRESS (class=$WINDOW_CLASS)" >&2
fi

exit 0
