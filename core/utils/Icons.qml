pragma Singleton

import qs.config
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    // Material Icon prefix convention for workspace icons
    // Use "mat:icon_name" in config to render via MaterialIcon component
    readonly property string materialIconPrefix: "mat:"

    // Parse icon string, stripping mat: prefix if present
    // Returns { useMaterial: bool, iconText: string }
    function parseIcon(icon: string): var {
        const usesMaterial = icon.startsWith(materialIconPrefix);
        const text = usesMaterial && icon.length > materialIconPrefix.length
            ? icon.slice(materialIconPrefix.length)
            : (usesMaterial ? "" : icon);
        return { useMaterial: usesMaterial, iconText: text };
    }

    // Check if an icon exists in the current theme
    // Returns true if the icon can be loaded, false otherwise
    function iconExists(iconName: string): bool {
        if (!iconName || iconName.length === 0) return false;
        // Use Quickshell.iconPath with check=true which returns empty string if icon doesn't exist
        const path = Quickshell.iconPath(iconName, true);
        return path && path.length > 0;
    }

    // Safe icon path getter that suppresses warnings for missing icons
    // Returns icon path if icon exists, fallback if fallback exists, empty string otherwise
    // Optimized to avoid redundant iconPath() calls
    function safeIconPath(icon: string, fallback: string): string {
        // Try primary icon first
        if (icon && icon.length > 0) {
            const path = Quickshell.iconPath(icon, true);
            if (path && path.length > 0) return path;
        }
        // Try fallback icon
        if (fallback && fallback.length > 0) {
            const path = Quickshell.iconPath(fallback, true);
            if (path && path.length > 0) return path;
        }
        // Return empty string to avoid warning - component should handle missing icons gracefully
        return "";
    }

    // Terminal emulator window classes for terminal app detection (all lowercase for efficient lookup)
    readonly property var terminalClasses: new Set([
        "com.mitchellh.ghostty", "ghostty", "kitty", "alacritty",
        "foot", "wezterm", "org.wezfurlong.wezterm", "gnome-terminal",
        "org.gnome.terminal", "konsole", "org.kde.konsole", "xterm",
        "urxvt", "st-256color", "st", "termite", "tilix"
    ])

    // Map of terminal app title keywords to their icon names
    // The first word of the terminal title is matched against these
    readonly property var terminalApps: ({
        // Editors
        "nvim": "nvim",
        "vim": "vim",
        "vi": "vim",
        "v": "nvim",
        "hx": "helix",
        "helix": "helix",
        "nano": "text-editor",
        "emacs": "emacs",
        // File managers
        "yazi": "yazi",
        "ranger": "ranger",
        "lf": "lf",
        "mc": "mc",
        "nnn": "nnn",
        "vifm": "vifm",
        // System monitors
        "htop": "htop",
        "btop": "btop",
        "top": "utilities-system-monitor",
        "nvtop": "nvtop",
        "gotop": "gotop",
        // Git tools
        "lazygit": "git",
        "tig": "git",
        "gitui": "git",
        // Docker/containers
        "lazydocker": "docker",
        "docker": "docker",
        "podman": "podman",
        // Programming languages/REPLs
        "python": "python",
        "python3": "python",
        "node": "nodejs",
        "ruby": "ruby",
        "irb": "ruby",
        "lua": "lua",
        "ghci": "haskell",
        // Other tools
        "man": "help-contents",
        "less": "text-x-generic",
        "ssh": "utilities-terminal",
        "sudo": "system-lock-screen"
    })

    readonly property var weatherIcons: ({
            "0": "clear_day",
            "1": "clear_day",
            "2": "partly_cloudy_day",
            "3": "cloud",
            "45": "foggy",
            "48": "foggy",
            "51": "rainy",
            "53": "rainy",
            "55": "rainy",
            "56": "rainy",
            "57": "rainy",
            "61": "rainy",
            "63": "rainy",
            "65": "rainy",
            "66": "rainy",
            "67": "rainy",
            "71": "cloudy_snowing",
            "73": "cloudy_snowing",
            "75": "snowing_heavy",
            "77": "cloudy_snowing",
            "80": "rainy",
            "81": "rainy",
            "82": "rainy",
            "85": "cloudy_snowing",
            "86": "snowing_heavy",
            "95": "thunderstorm",
            "96": "thunderstorm",
            "99": "thunderstorm"
        })

    readonly property var categoryIcons: ({
            WebBrowser: "web",
            Printing: "print",
            Security: "security",
            Network: "chat",
            Archiving: "archive",
            Compression: "archive",
            Development: "code",
            IDE: "code",
            TextEditor: "edit_note",
            Audio: "music_note",
            Music: "music_note",
            Player: "music_note",
            Recorder: "mic",
            Game: "sports_esports",
            FileTools: "files",
            FileManager: "files",
            Filesystem: "files",
            FileTransfer: "files",
            Settings: "settings",
            DesktopSettings: "settings",
            HardwareSettings: "settings",
            TerminalEmulator: "terminal",
            ConsoleOnly: "terminal",
            Utility: "build",
            Monitor: "monitor_heart",
            Midi: "graphic_eq",
            Mixer: "graphic_eq",
            AudioVideoEditing: "video_settings",
            AudioVideo: "music_video",
            Video: "videocam",
            Building: "construction",
            Graphics: "photo_library",
            "2DGraphics": "photo_library",
            RasterGraphics: "photo_library",
            TV: "tv",
            System: "host",
            Office: "content_paste"
        })

    function getAppIcon(name: string, fallback: string): string {
        const icon = DesktopEntries.heuristicLookup(name)?.icon;
        // Use safeIconPath to avoid warnings for missing icons
        if (fallback !== "undefined")
            return safeIconPath(icon, fallback);
        return safeIconPath(icon, "application-x-executable");
    }

    function getAppCategoryIcon(name: string, fallback: string): string {
        const categories = DesktopEntries.heuristicLookup(name)?.categories;

        if (categories)
            for (const [key, value] of Object.entries(categoryIcons))
                if (categories.includes(key))
                    return value;
        return fallback;
    }

    // Check if a window class represents a terminal emulator
    function isTerminal(windowClass: string): bool {
        if (!windowClass) return false;
        return terminalClasses.has(windowClass.toLowerCase());
    }

    // Resolve the appropriate icon for a window based on class and title
    // For terminals, attempts to detect the running app from the title
    // Returns the icon path (via safeIconPath) ready for use in IconImage
    function resolveWindowIcon(windowClass: string, windowTitle: string): string {
        // Terminal app detection
        if (isTerminal(windowClass) && windowTitle) {
            // Extract first word from title (handles formats like "nvim: file.ts" or "nvim file.ts")
            const firstWord = windowTitle.split(/[\s:\-\|]+/)[0]?.toLowerCase();
            if (firstWord && terminalApps.hasOwnProperty(firstWord)) {
                const appIconName = terminalApps[firstWord];
                // Try to get the app's actual icon
                const appIcon = DesktopEntries.heuristicLookup(appIconName)?.icon;
                if (appIcon) {
                    return safeIconPath(appIcon, windowClass);
                }
                // Fallback: try the icon name directly
                return safeIconPath(appIconName, windowClass);
            }
        }

        // Standard desktop entry lookup
        const entry = DesktopEntries.heuristicLookup(windowClass);
        if (entry?.icon) {
            return safeIconPath(entry.icon, "application-x-executable");
        }

        // Final fallback
        return safeIconPath(windowClass, "application-x-executable");
    }

    function getNetworkIcon(strength: int, isSecure = false): string {
        if (isSecure) {
            if (strength >= 80)
                return "network_wifi_locked";
            if (strength >= 60)
                return "network_wifi_3_bar_locked";
            if (strength >= 40)
                return "network_wifi_2_bar_locked";
            if (strength >= 20)
                return "network_wifi_1_bar_locked";
            return "signal_wifi_0_bar";
        } else {
            if (strength >= 80)
                return "network_wifi";
            if (strength >= 60)
                return "network_wifi_3_bar";
            if (strength >= 40)
                return "network_wifi_2_bar";
            if (strength >= 20)
                return "network_wifi_1_bar";
            return "signal_wifi_0_bar";
        }
    }

    function getBluetoothIcon(icon: string): string {
        if (icon.includes("headset") || icon.includes("headphones"))
            return "headphones";
        if (icon.includes("audio"))
            return "speaker";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("keyboard"))
            return "keyboard";
        return "bluetooth";
    }

    function getWeatherIcon(code: string): string {
        if (weatherIcons.hasOwnProperty(code))
            return weatherIcons[code];
        return "air";
    }

    function getNotifIcon(summary: string, urgency: int): string {
        summary = summary.toLowerCase();
        if (summary.includes("reboot"))
            return "restart_alt";
        if (summary.includes("recording"))
            return "screen_record";
        if (summary.includes("battery"))
            return "power";
        if (summary.includes("screenshot"))
            return "screenshot_monitor";
        if (summary.includes("welcome"))
            return "waving_hand";
        if (summary.includes("time") || summary.includes("a break"))
            return "schedule";
        if (summary.includes("installed"))
            return "download";
        if (summary.includes("update"))
            return "update";
        if (summary.includes("unable to"))
            return "deployed_code_alert";
        if (summary.includes("profile"))
            return "person";
        if (summary.includes("file"))
            return "folder_copy";
        if (urgency === NotificationUrgency.Critical)
            return "release_alert";
        return "chat";
    }

    function getVolumeIcon(volume: real, isMuted: bool): string {
        if (isMuted)
            return "no_sound";
        if (volume >= 0.5)
            return "volume_up";
        if (volume > 0)
            return "volume_down";
        return "volume_mute";
    }

    function getMicVolumeIcon(volume: real, isMuted: bool): string {
        if (!isMuted && volume > 0)
            return "mic";
        return "mic_off";
    }

    // Private helper for icon lookup in config arrays
    function _lookupIconInList(name: string, iconList: list<var>): string {
        for (const iconConfig of iconList) {
            if (iconConfig.name === name) return iconConfig.icon;
        }
        return "";
    }

    function getSpecialWsIcon(name: string): string {
        name = name.toLowerCase().slice("special:".length);

        const configIcon = _lookupIconInList(name, Config.bar.workspaces.specialWorkspaceIcons);
        if (configIcon) return configIcon;

        // Fallbacks for common special workspace names
        const fallbacks = {
            "special": "mat:star",
            "communication": "mat:forum",
            "music": "mat:music_cast",
            "todo": "mat:checklist",
            "sysmon": "mat:monitor_heart"
        };
        return fallbacks[name] ?? name[0]?.toUpperCase() ?? "mat:star";
    }

    function getNamedWsIcon(name: string): string {
        return _lookupIconInList(name, Config.bar.workspaces.namedWorkspaceIcons);
    }

    function romanize(num: int): string {
        // Validate input - only positive integers supported
        if (typeof num !== 'number' || isNaN(num)) return "";
        num = Math.floor(num);
        if (num <= 0) return "";

        const key = [
            "", "C", "CC", "CCC", "CD", "D", "DC", "DCC", "DCCC", "CM",
            "", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC",
            "", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"
        ];
        let digits = String(num).split("");
        let roman = "";
        let i = 3;
        while (i--) roman = (key[+digits.pop() + i * 10] || "") + roman;
        return Array(+digits.join("") + 1).join("M") + roman;
    }

    function getTrayIcon(id: string, icon: string): string {
        for (const sub of Config.bar.tray.iconSubs)
            if (sub.id === id)
                return sub.image ? Qt.resolvedUrl(sub.image) : Quickshell.iconPath(sub.icon);

        if (icon.includes("?path=")) {
            const [name, path] = icon.split("?path=");
            icon = Qt.resolvedUrl(`${path}/${name.slice(name.lastIndexOf("/") + 1)}`);
        }
        return icon;
    }
}
