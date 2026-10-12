pragma Singleton

import Quickshell
import QtQuick

// The bar's icon family: Phosphor Light (MIT, @phosphor-icons/web 2.1.2,
// src/light/Phosphor-Light.ttf, vendored in assets/fonts with its licence).
//
// The bar draws glyphs through BarIcon, which takes a MATERIAL SYMBOLS name and
// looks it up here. The vocabulary stays Material on purpose: Icons.getVolumeIcon,
// Icons.getNetworkIcon, Weather.icon, PowerMode.activeMode.icon and the
// namedWorkspaceIcons in shell.json all speak Material names, and the popouts
// and the dashboard keep rendering those names in Material Symbols. One table
// here restyles the bar without forking every helper into two vocabularies.
//
// A name with no entry is not an error: BarIcon falls back to Material Symbols
// at a matching thin weight, so a new state shows a slightly different glyph
// rather than tofu. To add an entry, take the codepoint from the `content` of
// `.ph-light.ph-<name>:before` in that package's src/light/style.css. Phosphor
// ships no ligatures, so the codepoint is the only way to address a glyph.
Singleton {
    id: root

    readonly property FontLoader phosphorLoader: FontLoader {
        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/fonts/Phosphor-Light.ttf`)
    }

    // Two tones carry the bar's hierarchy: a glyph or unit that labels a
    // number recedes, the number itself stays at full strength. Status glyphs
    // stand alone, so they sit nearer full strength.
    readonly property real secondaryAlpha: 0.55
    readonly property real statusAlpha: 0.85

    // Empty until the font has loaded; BarIcon renders Material until then.
    readonly property string family: phosphorLoader.status === FontLoader.Ready ? phosphorLoader.name : ""

    // Material Symbols name -> Phosphor Light codepoint. The comment above
    // each entry is the Phosphor name. Several Material states share one
    // Phosphor glyph where Phosphor draws fewer steps (Wi-Fi bars, battery
    // levels, charging).
    readonly property var codepoints: ({
            // Clock, date and weather (Clock, Date, TimePill <- Weather.icon)

            // clock
            "schedule": 0xE19A,
            // calendar-blank
            "calendar_month": 0xE10A,
            // sun
            "clear_day": 0xE472,
            // cloud-sun
            "partly_cloudy_day": 0xE540,
            // cloud
            "cloud": 0xE1AA,
            // cloud-fog
            "foggy": 0xE53C,
            // cloud-rain
            "rainy": 0xE1B4,
            // cloud-snow
            "cloudy_snowing": 0xE1B8,
            // snowflake
            "snowing_heavy": 0xE5AA,
            // cloud-lightning
            "thunderstorm": 0xE1B2,
            // wind
            "air": 0xE5D2,
            // cloud-warning
            "cloud_alert": 0xEA98,
            // System readouts (CpuStatus, RamUsage, AvailableUpdates)

            // cpu
            "developer_board": 0xE610,
            // memory
            "memory_alt": 0xE9C4,
            // arrows-clockwise
            "sync": 0xE094,
            // warning-circle
            "error": 0xE4E2,
            // check-circle
            "check_box": 0xE184,
            // arrow-circle-down
            "download": 0xE028,
            // Status icons (StatusIcons <- Icons.get*Icon, PowerMode.activeMode.icon)

            // arrow-fat-line-up
            "keyboard_capslock_badge": 0xE522,
            // number-circle-one
            "looks_one": 0xE36A,
            // speaker-high
            "volume_up": 0xE44A,
            // speaker-low
            "volume_down": 0xE44C,
            // speaker-none
            "volume_mute": 0xE44E,
            // speaker-slash
            "no_sound": 0xE45A,
            // microphone
            "mic": 0xE326,
            // microphone-slash
            "mic_off": 0xE328,
            // wifi-high
            "network_wifi": 0xE4EA,
            // wifi-medium
            "network_wifi_3_bar": 0xE4EE,
            // wifi-medium
            "network_wifi_2_bar": 0xE4EE,
            // wifi-low
            "network_wifi_1_bar": 0xE4EC,
            // wifi-none
            "signal_wifi_0_bar": 0xE4F0,
            // wifi-high
            "network_wifi_locked": 0xE4EA,
            // wifi-medium
            "network_wifi_3_bar_locked": 0xE4EE,
            // wifi-medium
            "network_wifi_2_bar_locked": 0xE4EE,
            // wifi-low
            "network_wifi_1_bar_locked": 0xE4EC,
            // wifi-slash
            "wifi_off": 0xE4F2,
            // plugs-connected
            "cable": 0xEB5A,
            // bluetooth
            "bluetooth": 0xE0DA,
            // bluetooth-connected
            "bluetooth_connected": 0xE0DC,
            // bluetooth-slash
            "bluetooth_disabled": 0xE0DE,
            // headphones
            "headphones": 0xE2A6,
            // speaker-hifi
            "speaker": 0xEA08,
            // device-mobile
            "smartphone": 0xE1E0,
            // mouse
            "mouse": 0xE33A,
            // keyboard
            "keyboard": 0xE2D8,
            // moon
            "bedtime": 0xE330,
            // leaf
            "energy_savings_leaf": 0xE2DA,
            // scales
            "balance": 0xE750,
            // rocket-launch
            "rocket_launch": 0xE3FE,
            // battery-full
            "battery_full": 0xE0C0,
            // battery-high
            "battery_6_bar": 0xE0C2,
            // battery-high
            "battery_5_bar": 0xE0C2,
            // battery-medium
            "battery_4_bar": 0xE0C6,
            // battery-medium
            "battery_3_bar": 0xE0C6,
            // battery-low
            "battery_2_bar": 0xE0C4,
            // battery-low
            "battery_1_bar": 0xE0C4,
            // battery-empty
            "battery_0_bar": 0xE0BE,
            // battery-charging
            "battery_charging_full": 0xE0BA,
            // battery-charging
            "battery_charging_90": 0xE0BA,
            // battery-charging
            "battery_charging_80": 0xE0BA,
            // battery-charging
            "battery_charging_60": 0xE0BA,
            // battery-charging
            "battery_charging_50": 0xE0BA,
            // battery-charging
            "battery_charging_30": 0xE0BA,
            // battery-charging
            "battery_charging_20": 0xE0BA,
            // waveform
            "graphic_eq": 0xE802,
            // power
            "power_settings_new": 0xE3DA,
            // caret-up
            "expand_less": 0xE13C,
            // Workspaces (namedWorkspaceIcons / specialWorkspaceIcons / getSpecialWsIcon fallbacks, fullscreen badge)

            // folder-simple
            "folder": 0xE25A,
            // folder-open
            "folder_open": 0xE256,
            // globe-hemisphere-west
            "public": 0xE28C,
            // globe-hemisphere-west
            "language": 0xE28C,
            // cube
            "deployed_code": 0xE1DA,
            // phone
            "phone": 0xE3B8,
            // phone
            "call": 0xE3B8,
            // book-open
            "auto_stories": 0xE0E6,
            // game-controller
            "sports_esports": 0xE26E,
            // music-notes
            "library_music": 0xE340,
            // music-notes
            "music_cast": 0xE340,
            // mask-happy
            "theater_comedy": 0xE9F4,
            // chat-circle
            "chat": 0xE168,
            // chats
            "forum": 0xE17C,
            // palette
            "palette": 0xE6C8,
            // paint-roller
            "format_paint": 0xE6F4,
            // crosshair
            "target": 0xE1D6,
            // gear-six
            "settings": 0xE272,
            // sliders-horizontal
            "tune": 0xE434,
            // pencil-simple
            "edit": 0xE3B4,
            // lightbulb
            "lightbulb": 0xE2DC,
            // star
            "star": 0xE46A,
            // list-checks
            "checklist": 0xEADC,
            // heartbeat
            "monitor_heart": 0xE2AC,
            // corners-out
            "fullscreen": 0xE1D0
        })

    // 0 when the name has no Phosphor translation.
    function codepointFor(materialName: string): int {
        return root.codepoints[materialName] ?? 0;
    }
}
