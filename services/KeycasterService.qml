pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Keycaster service for displaying keyboard and mouse button events.
///
/// Spawns `showmethekey-cli` as a subprocess to capture keyboard and mouse input.
/// Tracks held modifiers and maintains a FIFO history of key combinations.
/// Mouse button events (left, right, middle click) are displayed as graphical icons.
///
/// Setup: User must be in the `input` group to read /dev/input:
///   sudo usermod -aG input $USER
///   (log out and back in for changes to take effect)
Singleton {
    id: root

    /// Whether the keycaster is currently active (visible and capturing)
    property bool active: false

    /// Key history for display - each entry has:
    ///   { key: string, mouseButton: string, timestamp: int, keyId: int }
    /// mouseButton is "" for keyboard events, "left"/"right"/"middle" for mouse clicks.
    /// For mouse events, key contains only the modifier prefix (e.g. "⌘+" or "").
    /// Older entries are at lower indices, newest at the end
    readonly property alias keyHistory: keyHistoryModel

    /// Currently held modifiers text (cached, updates on modifier change)
    readonly property alias heldModifiersText: root._cachedHeldModifiersText

    /// Whether any modifiers are currently held
    readonly property bool hasHeldModifiers: _cachedHeldModifiersText.length > 0

    // ─────────────────────────────────────────────────────────────────────────
    // Configuration with validated defaults
    // ─────────────────────────────────────────────────────────────────────────

    readonly property var _config: ({
        historyLength: Config.keycaster?.historyLength ?? 5,
        fadeoutDelay: Config.keycaster?.fadeoutDelay ?? 2000,
        fadeoutDuration: Config.keycaster?.fadeoutDuration ?? 500,
        showMouseClicks: Config.keycaster?.showMouseClicks ?? true
    })

    // ─────────────────────────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────────────────────────

    // Unique ID counter with wraparound to prevent unbounded growth
    readonly property int _maxKeyId: 1000000
    property int _nextKeyId: 0

    // Modifier tracking state (individual properties for fine-grained change detection)
    property bool _modSuper: false
    property bool _modCtrl: false
    property bool _modAlt: false
    property bool _modShift: false

    // Cached modifier text (updated when any modifier changes)
    property string _cachedHeldModifiersText: ""

    // Track if showmethekey is missing (to avoid repeated error spam)
    property bool _showmetekeyMissing: false

    // Update cached modifier text when any modifier changes
    on_ModSuperChanged: _updateModifierText()
    on_ModCtrlChanged: _updateModifierText()
    on_ModAltChanged: _updateModifierText()
    on_ModShiftChanged: _updateModifierText()

    function _updateModifierText(): void {
        const parts = [];
        if (_modSuper) parts.push(_modifierSymbols.super);
        if (_modCtrl) parts.push(_modifierSymbols.ctrl);
        if (_modAlt) parts.push(_modifierSymbols.alt);
        if (_modShift) parts.push(_modifierSymbols.shift);
        _cachedHeldModifiersText = parts.join("+");
    }

    // Clear mouse click entries from history when showMouseClicks is disabled
    readonly property bool _showMouseClicks: _config.showMouseClicks
    on_ShowMouseClicksChanged: {
        if (!_showMouseClicks) {
            for (let i = keyHistoryModel.count - 1; i >= 0; i--) {
                if (keyHistoryModel.get(i).mouseButton !== "")
                    keyHistoryModel.remove(i);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Key name mappings
    // ─────────────────────────────────────────────────────────────────────────

    readonly property var _keyNameMap: ({
        // Letters - just show uppercase
        "KEY_A": "A", "KEY_B": "B", "KEY_C": "C", "KEY_D": "D", "KEY_E": "E",
        "KEY_F": "F", "KEY_G": "G", "KEY_H": "H", "KEY_I": "I", "KEY_J": "J",
        "KEY_K": "K", "KEY_L": "L", "KEY_M": "M", "KEY_N": "N", "KEY_O": "O",
        "KEY_P": "P", "KEY_Q": "Q", "KEY_R": "R", "KEY_S": "S", "KEY_T": "T",
        "KEY_U": "U", "KEY_V": "V", "KEY_W": "W", "KEY_X": "X", "KEY_Y": "Y",
        "KEY_Z": "Z",

        // Numbers
        "KEY_0": "0", "KEY_1": "1", "KEY_2": "2", "KEY_3": "3", "KEY_4": "4",
        "KEY_5": "5", "KEY_6": "6", "KEY_7": "7", "KEY_8": "8", "KEY_9": "9",

        // Function keys
        "KEY_F1": "F1", "KEY_F2": "F2", "KEY_F3": "F3", "KEY_F4": "F4",
        "KEY_F5": "F5", "KEY_F6": "F6", "KEY_F7": "F7", "KEY_F8": "F8",
        "KEY_F9": "F9", "KEY_F10": "F10", "KEY_F11": "F11", "KEY_F12": "F12",

        // Navigation
        "KEY_UP": "↑", "KEY_DOWN": "↓", "KEY_LEFT": "←", "KEY_RIGHT": "→",
        "KEY_HOME": "Home", "KEY_END": "End",
        "KEY_PAGEUP": "PgUp", "KEY_PAGEDOWN": "PgDn",

        // Common keys
        "KEY_SPACE": "␣", "KEY_ENTER": "⏎", "KEY_RETURN": "⏎",
        "KEY_TAB": "Tab", "KEY_BACKSPACE": "⌫", "KEY_DELETE": "Del",
        "KEY_ESCAPE": "Esc", "KEY_INSERT": "Ins",
        "KEY_CAPSLOCK": "CapsLock", "KEY_NUMLOCK": "NumLock",
        "KEY_SCROLLLOCK": "ScrLock", "KEY_PRINT": "PrtSc", "KEY_PAUSE": "Pause",

        // Punctuation
        "KEY_MINUS": "-", "KEY_EQUAL": "=", "KEY_LEFTBRACE": "[", "KEY_RIGHTBRACE": "]",
        "KEY_BACKSLASH": "\\", "KEY_SEMICOLON": ";", "KEY_APOSTROPHE": "'",
        "KEY_GRAVE": "`", "KEY_COMMA": ",", "KEY_DOT": ".", "KEY_SLASH": "/",

        // Modifiers (shown only as held previews, not added to history)
        "KEY_LEFTCTRL": "Ctrl", "KEY_RIGHTCTRL": "Ctrl",
        "KEY_LEFTALT": "Alt", "KEY_RIGHTALT": "Alt",
        "KEY_LEFTSHIFT": "Shift", "KEY_RIGHTSHIFT": "Shift",
        "KEY_LEFTMETA": "Super", "KEY_RIGHTMETA": "Super",

        // Numpad
        "KEY_KP0": "Num0", "KEY_KP1": "Num1", "KEY_KP2": "Num2", "KEY_KP3": "Num3",
        "KEY_KP4": "Num4", "KEY_KP5": "Num5", "KEY_KP6": "Num6", "KEY_KP7": "Num7",
        "KEY_KP8": "Num8", "KEY_KP9": "Num9",
        "KEY_KPPLUS": "Num+", "KEY_KPMINUS": "Num-", "KEY_KPASTERISK": "Num*",
        "KEY_KPSLASH": "Num/", "KEY_KPDOT": "Num.", "KEY_KPENTER": "NumEnter",

        // Media keys
        "KEY_MUTE": "Mute", "KEY_VOLUMEDOWN": "Vol-", "KEY_VOLUMEUP": "Vol+",
        "KEY_PLAYPAUSE": "Play/Pause", "KEY_NEXTSONG": "Next", "KEY_PREVIOUSSONG": "Prev",
        "KEY_STOPCD": "Stop"
    })

    // Modifier key codes for tracking held state
    readonly property var _modifierKeys: ({
        "KEY_LEFTCTRL": "ctrl", "KEY_RIGHTCTRL": "ctrl",
        "KEY_LEFTALT": "alt", "KEY_RIGHTALT": "alt",
        "KEY_LEFTSHIFT": "shift", "KEY_RIGHTSHIFT": "shift",
        "KEY_LEFTMETA": "super", "KEY_RIGHTMETA": "super"
    })

    // Mac-style modifier symbols for compact display
    readonly property var _modifierSymbols: ({
        "super": "⌘",   // U+2318 Command key
        "ctrl": "⌃",    // U+2303 Control key
        "alt": "⌥",     // U+2325 Option key
        "shift": "⇧"    // U+21E7 Shift key
    })

    // Mouse button codes → button identifiers for MouseClickIcon
    readonly property var _mouseButtonMap: ({
        "BTN_LEFT": "left",
        "BTN_RIGHT": "right",
        "BTN_MIDDLE": "middle"
    })

    // ─────────────────────────────────────────────────────────────────────────
    // Helper functions
    // ─────────────────────────────────────────────────────────────────────────

    /// Reset all modifier states to released
    function resetModifiers(): void {
        _modSuper = false;
        _modCtrl = false;
        _modAlt = false;
        _modShift = false;
    }

    /// Normalize a key code to display name
    function normalizeKeyName(keyCode: string): string {
        return _keyNameMap[keyCode] ?? keyCode.replace("KEY_", "");
    }

    /// Check if a key code is a modifier
    function isModifier(keyCode: string): bool {
        return keyCode in _modifierKeys;
    }

    /// Check if a key code is a mouse button
    function isMouseButton(keyCode: string): bool {
        return keyCode in _mouseButtonMap;
    }

    /// Add a key combination to history
    /// mouseButton: "" for keyboard events, "left"/"right"/"middle" for mouse clicks
    function addKeyToHistory(keyText: string, mouseButton: string): void {
        // Remove oldest if at capacity
        while (keyHistoryModel.count >= _config.historyLength) {
            keyHistoryModel.remove(0);
        }

        // Add new entry with wraparound ID
        keyHistoryModel.append({
            key: keyText,
            mouseButton: mouseButton,
            timestamp: Date.now(),
            keyId: _nextKeyId
        });

        // Cycle ID with wraparound to prevent unbounded growth
        _nextKeyId = (_nextKeyId + 1) % _maxKeyId;
    }

    /// Build full key combination text with modifiers
    function buildKeyCombo(keyName: string): string {
        const parts = [];
        if (_modSuper) parts.push(_modifierSymbols.super);
        if (_modCtrl) parts.push(_modifierSymbols.ctrl);
        if (_modAlt) parts.push(_modifierSymbols.alt);
        if (_modShift) parts.push(_modifierSymbols.shift);
        parts.push(keyName);
        return parts.join("+");
    }

    /// Build modifier prefix text for mouse click events (e.g. "⌘+⇧+" or "")
    function buildModifierPrefix(): string {
        const parts = [];
        if (_modSuper) parts.push(_modifierSymbols.super);
        if (_modCtrl) parts.push(_modifierSymbols.ctrl);
        if (_modAlt) parts.push(_modifierSymbols.alt);
        if (_modShift) parts.push(_modifierSymbols.shift);
        return parts.length > 0 ? parts.join("+") + "+" : "";
    }

    /// Process a key event from showmethekey-cli
    function processKeyEvent(keyCode: string, eventType: string): void {
        const isPress = eventType === "pressed";

        // Handle modifier key state tracking
        if (keyCode in _modifierKeys) {
            const modName = _modifierKeys[keyCode];
            if (modName === "super") _modSuper = isPress;
            else if (modName === "ctrl") _modCtrl = isPress;
            else if (modName === "alt") _modAlt = isPress;
            else if (modName === "shift") _modShift = isPress;
            // Don't add modifiers to history on their own
            return;
        }

        // Handle mouse button events
        if (keyCode in _mouseButtonMap) {
            if (isPress && _config.showMouseClicks) {
                const buttonName = _mouseButtonMap[keyCode];
                const modPrefix = buildModifierPrefix();
                addKeyToHistory(modPrefix, buttonName);
            }
            return;
        }

        // Log unrecognized BTN_ codes for debugging (e.g. BTN_SIDE, BTN_EXTRA)
        if (keyCode.startsWith("BTN_")) {
            console.warn("Keycaster: Unsupported mouse button:", keyCode);
            return;
        }

        // Only process key presses for non-modifiers
        if (isPress) {
            const keyName = normalizeKeyName(keyCode);
            const keyCombo = buildKeyCombo(keyName);
            addKeyToHistory(keyCombo, "");
        }
    }

    /// Clear all key history and reset modifiers
    function clearHistory(): void {
        keyHistoryModel.clear();
        resetModifiers();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Key history model
    // ─────────────────────────────────────────────────────────────────────────

    ListModel {
        id: keyHistoryModel
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Subprocess for showmethekey-cli
    // ─────────────────────────────────────────────────────────────────────────

    Process {
        id: keyCaptureProcess

        // Use absolute path to prevent PATH manipulation attacks
        command: ["/usr/bin/showmethekey-cli"]

        // Don't run if showmethekey is missing
        running: root.active && !root._showmetekeyMissing

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line) return;

                try {
                    // showmethekey-cli outputs JSON per key/button event
                    // Keyboard: {"key_name": "KEY_A", "state_name": "PRESSED", "event_name": "KEYBOARD_KEY"}
                    // Mouse:    {"key_name": "BTN_LEFT", "state_name": "PRESSED", "event_name": "POINTER_BUTTON"}
                    const event = JSON.parse(line);

                    // Validate required fields
                    const keyName = event.key_name;
                    const stateName = event.state_name;

                    if (!keyName || typeof keyName !== 'string') {
                        console.warn("Keycaster: Missing or invalid key_name in event");
                        return;
                    }

                    if (!stateName || typeof stateName !== 'string') {
                        console.warn("Keycaster: Missing or invalid state_name in event");
                        return;
                    }

                    const normalizedState = stateName.toLowerCase();
                    if (normalizedState !== "pressed" && normalizedState !== "released") {
                        console.warn("Keycaster: Invalid state_name:", stateName);
                        return;
                    }

                    root.processKeyEvent(keyName, normalizedState);
                } catch (e) {
                    // Not JSON or malformed - ignore
                    console.warn("Keycaster: Failed to parse key event:", line);
                }
            }
        }

        onExited: (code, status) => {
            if (code === 127) {
                // Command not found
                console.error("Keycaster: showmethekey-cli not installed");
                console.error("  Install with: paru -S showmethekey");
                root._showmetekeyMissing = true;
                root.active = false;  // Stop the service immediately
            } else if (code !== 0 && root.active) {
                console.warn("Keycaster: showmethekey-cli exited with code", code);
            }
            // Clear modifiers on any exit to avoid stuck state
            root.resetModifiers();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State management
    // ─────────────────────────────────────────────────────────────────────────

    onActiveChanged: {
        if (!active) {
            // Small delay before clearing to allow final key to display
            clearTimer.start();
        } else {
            clearTimer.stop();
            // Clear any stale state from previous session
            resetModifiers();
        }
    }

    // Timer to clear history after hiding (allows user to see last keys briefly)
    Timer {
        id: clearTimer
        interval: 500
        onTriggered: root.clearHistory()
    }
}
