# HyprWhspr QuickShell Integration - Implementation Guide

## Overview

This document provides the technical knowledge needed to implement a native QuickShell bar indicator for hyprwhspr (speech-to-text tool), replacing or complementing the GTK4 mic-osd visualization.

---

## Part 1: HyprWhspr Communication Protocol

### State Files (Primary Integration Point)

hyprwhspr exposes state via files in `~/.config/hyprwhspr/`:

| File | Content | Purpose |
|------|---------|---------|
| `recording_status` | `"true"` or `"false"` | Current recording state |
| `audio_level` | Float (0.0-1.0) | Real-time audio amplitude |
| `recording_control` | FIFO pipe | Send commands to hyprwhspr |

### Reading Recording State

```qml
// Poll recording_status file
FileView {
    id: recordingStatus
    path: Qt.resolvedUrl("~/.config/hyprwhspr/recording_status")
    // Or use: Quickshell.watchFile() for change notifications
}

property bool isRecording: recordingStatus.text?.trim() === "true"
```

### Reading Audio Level

```qml
// Poll audio_level file for visualization
FileView {
    id: audioLevel
    path: Qt.resolvedUrl("~/.config/hyprwhspr/audio_level")
}

property real currentLevel: parseFloat(audioLevel.text?.trim() || "0")
```

### Alternative: IPC via FIFO

hyprwhspr listens on `~/.config/hyprwhspr/recording_control` FIFO:

```bash
# Start recording
echo "start" > ~/.config/hyprwhspr/recording_control

# Stop recording
echo "stop" > ~/.config/hyprwhspr/recording_control

# Toggle recording
echo "toggle" > ~/.config/hyprwhspr/recording_control
```

In QML:
```qml
function toggleRecording() {
    Quickshell.execDetached(["sh", "-c", "echo toggle > ~/.config/hyprwhspr/recording_control"])
}
```

---

## Part 2: GTK4 Mic-OSD Implementation Reference

### What the GTK4 Version Does

1. **Daemon Architecture**: Persistent process, signal-based show/hide (SIGUSR1/SIGUSR2)
2. **Audio Monitoring**: Captures mic via sounddevice, 60 FPS updates
3. **Visualization**: 32 vertical bars with gradient colors, pulsing recording dot
4. **Layer Shell**: Overlay layer, bottom-center position, click-through

### Visual Design Specifications

```
┌─────────────────────────────────────────────────────────────┐
│  ●  ▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌                        │
│     └─ 32 bars with cyan→green gradient ─┘                  │
│  └─ Pulsing red dot                                         │
└─────────────────────────────────────────────────────────────┘

Dimensions: 400 x 68 pixels
Position: Bottom center, 130px from bottom edge
Background: Dark semi-transparent (#1a1a26f2)
Border: Cyan (#33ccff)
```

### Color Palette (from GTK4 theme)

| Element | Color | RGB |
|---------|-------|-----|
| Background | Dark blue-gray | `rgba(0.1, 0.1, 0.15, 0.95)` |
| Recording dot | Red | `rgb(1.0, 0.2, 0.33)` |
| Bar gradient left | Cyan | `rgb(0.2, 0.8, 1.0)` |
| Bar gradient right | Green | `rgb(0.0, 1.0, 0.6)` |
| Border | Cyan | `rgb(0.2, 0.8, 1.0)` |

### Animation Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Update rate | 60 FPS | 16ms timer |
| Bar count | 32 | Vertical bars |
| Rise rate | 0.5 | Quick attack |
| Decay rate | 0.85 | Slow fall |
| Pulse speed | +0.15 rad/frame | Recording dot |
| Amplification | 4.0x | Boosts quiet audio |

---

## Part 3: QuickShell Implementation Strategy

### Option A: Bar Indicator Widget (Recommended)

A minimal status icon in the bar that shows recording state:

**Location**: `/home/jc/.config/quickshell/symmetria/modules/bar/components/HyprWhspr.qml`

**Features**:
- Microphone icon that changes when recording
- Pulsing animation during recording
- Optional: Mini audio level bar
- Click to toggle recording
- Tooltip with status info

### Option B: Full Visualization Popup

A popout panel similar to the GTK4 version:

**Location**: `/home/jc/.config/quickshell/symmetria/modules/bar/popouts/HyprWhsprViz.qml`

**Features**:
- Full waveform visualization with bars
- Appears automatically when recording starts
- Uses Canvas or custom QML drawing

### Option C: Drawer/Panel

A dedicated drawer with controls and visualization:

**Location**: `/home/jc/.config/quickshell/symmetria/modules/drawers/HyprWhspr.qml`

---

## Part 4: Implementation Details

### Service Definition

Create a service to manage hyprwhspr state:

**File**: `/home/jc/.config/quickshell/symmetria/services/HyprWhspr.qml`

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // State properties
    property bool isRecording: false
    property real audioLevel: 0.0
    property bool available: recordingStatusFile.exists

    // Ref counting for audio level polling
    property int refCount: 0

    // Recording status file watcher
    FileView {
        id: recordingStatusFile
        path: Quickshell.env("HOME") + "/.config/hyprwhspr/recording_status"
        watchChanges: true

        onTextChanged: {
            root.isRecording = text?.trim() === "true"
        }
    }

    // Audio level polling (only when refCount > 0)
    Timer {
        interval: 16  // 60 FPS
        running: root.refCount > 0 && root.isRecording
        repeat: true

        onTriggered: {
            audioLevelFile.reload()
        }
    }

    FileView {
        id: audioLevelFile
        path: Quickshell.env("HOME") + "/.config/hyprwhspr/audio_level"

        onTextChanged: {
            const level = parseFloat(text?.trim() || "0")
            root.audioLevel = Math.max(0, Math.min(1, level))
        }
    }

    // Control functions
    function toggle(): void {
        Quickshell.execDetached(["sh", "-c",
            "echo toggle > ~/.config/hyprwhspr/recording_control"])
    }

    function start(): void {
        Quickshell.execDetached(["sh", "-c",
            "echo start > ~/.config/hyprwhspr/recording_control"])
    }

    function stop(): void {
        Quickshell.execDetached(["sh", "-c",
            "echo stop > ~/.config/hyprwhspr/recording_control"])
    }
}
```

### Bar Widget Component

**File**: `/home/jc/.config/quickshell/symmetria/modules/bar/components/HyprWhspr.qml`

```qml
pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services
import qs.config

MouseArea {
    id: root

    property color colour: HyprWhspr.isRecording
        ? Colours.palette.m3error  // Red when recording
        : Colours.palette.m3tertiary

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    hoverEnabled: true

    // Only show if hyprwhspr is available
    visible: HyprWhspr.available

    // Subscribe to service
    Ref {
        service: HyprWhspr
    }

    onClicked: HyprWhspr.toggle()

    Row {
        id: content
        spacing: Appearance.spacing.small

        // Microphone icon with pulse animation
        MaterialIcon {
            id: micIcon
            anchors.verticalCenter: parent.verticalCenter
            text: HyprWhspr.isRecording ? "mic" : "mic_none"
            color: root.colour

            // Pulse animation when recording
            SequentialAnimation on opacity {
                running: HyprWhspr.isRecording
                loops: Animation.Infinite

                NumberAnimation {
                    from: 1.0; to: 0.5
                    duration: 500
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 0.5; to: 1.0
                    duration: 500
                    easing.type: Easing.InOutSine
                }
            }
        }

        // Optional: Mini audio level bar
        Rectangle {
            visible: HyprWhspr.isRecording
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 4
            radius: 2
            color: Colours.palette.m3surfaceContainer

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * HyprWhspr.audioLevel
                height: parent.height
                radius: parent.radius
                color: root.colour

                Behavior on width {
                    NumberAnimation {
                        duration: 50
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }

    Tooltip {
        target: root
        text: HyprWhspr.isRecording
            ? "Recording... (click to stop)"
            : "Click to start dictation"
    }
}
```

### Full Visualization Component (Optional)

**File**: `/home/jc/.config/quickshell/symmetria/modules/bar/popouts/HyprWhsprViz.qml`

```qml
pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services

Rectangle {
    id: root

    width: 400
    height: 68
    radius: Appearance.rounding.medium
    color: Qt.rgba(0.1, 0.1, 0.15, 0.95)
    border.color: Colours.palette.m3primary
    border.width: 1

    visible: HyprWhspr.isRecording

    Ref {
        service: HyprWhspr
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        // Recording dot
        Rectangle {
            id: recordingDot
            width: 12
            height: 12
            radius: 6
            color: "#ff3456"
            anchors.verticalCenter: parent.verticalCenter

            SequentialAnimation on opacity {
                running: true
                loops: Animation.Infinite

                NumberAnimation { from: 1; to: 0.4; duration: 600 }
                NumberAnimation { from: 0.4; to: 1; duration: 600 }
            }
        }

        // Audio bars
        Row {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: 32

                Rectangle {
                    required property int index

                    width: 8
                    height: Math.max(4, 50 * HyprWhspr.audioLevel * (0.5 + 0.5 * Math.random()))
                    radius: 2
                    anchors.bottom: parent.bottom

                    // Gradient from cyan to green
                    color: Qt.rgba(
                        0.2 * (1 - index/31) + 0.0 * (index/31),
                        0.8 * (1 - index/31) + 1.0 * (index/31),
                        1.0 * (1 - index/31) + 0.6 * (index/31),
                        0.9
                    )

                    Behavior on height {
                        NumberAnimation {
                            duration: 50
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }
        }
    }
}
```

---

## Part 5: Integration Steps

### Step 1: Create Service

1. Create `/home/jc/.config/quickshell/symmetria/services/HyprWhspr.qml`
2. Add to qmldir if needed
3. Import in components that need it

### Step 2: Create Bar Widget

1. Create `/home/jc/.config/quickshell/symmetria/modules/bar/components/HyprWhspr.qml`
2. Register in Bar.qml BarLoader switch:
   ```qml
   case "hyprwhspr": return hyprwhsprComp;
   ```
3. Add Component definition:
   ```qml
   Component {
       id: hyprwhsprComp
       HyprWhspr {}
   }
   ```

### Step 3: Add Config

Edit `/home/jc/.config/quickshell/symmetria/config/BarConfig.qml`:

```qml
property list<var> entries: [
    // ... existing entries
    { id: "hyprwhspr", enabled: true },
    // ... rest
]
```

### Step 4: Optional - Disable GTK4 OSD

In hyprwhspr config (`~/.config/hyprwhspr/config.json`):
```json
{
    "mic_osd_enabled": false
}
```

---

## Part 6: Advanced Features

### Audio Level Smoothing

For smoother visualization, apply exponential smoothing:

```qml
property real smoothedLevel: 0
property real rawLevel: HyprWhspr.audioLevel

onRawLevelChanged: {
    if (rawLevel > smoothedLevel) {
        // Fast attack
        smoothedLevel = 0.5 * rawLevel + 0.5 * smoothedLevel
    } else {
        // Slow decay
        smoothedLevel = 0.15 * rawLevel + 0.85 * smoothedLevel
    }
}
```

### Toast Notifications

Show toast when transcription completes:

```qml
Connections {
    target: HyprWhspr

    function onIsRecordingChanged() {
        if (!HyprWhspr.isRecording) {
            // Recording just stopped - transcription happening
            Toaster.info("Transcribing...")
        }
    }
}
```

### IPC Handler

Add IPC commands for external control:

```qml
// In Shortcuts.qml
IpcHandler {
    target: "hyprwhspr"

    function toggle(): void {
        HyprWhspr.toggle()
    }

    function start(): void {
        HyprWhspr.start()
    }

    function stop(): void {
        HyprWhspr.stop()
    }
}
```

Usage: `symmetria shell hyprwhspr toggle`

---

## Part 7: Testing

### Verify File Watching

```bash
# Check recording status file exists
cat ~/.config/hyprwhspr/recording_status

# Check audio level updates (while recording)
watch -n 0.1 cat ~/.config/hyprwhspr/audio_level
```

### Test FIFO Control

```bash
# Toggle recording via FIFO
echo toggle > ~/.config/hyprwhspr/recording_control
```

### Verify Service Running

```bash
systemctl --user status hyprwhspr.service
```

---

## Summary

This integration leverages hyprwhspr's file-based state exposure to create a native QuickShell indicator. The recommended approach is:

1. **Service** (`HyprWhspr.qml`) - Watches state files, provides reactive properties
2. **Bar Widget** (`HyprWhspr.qml`) - Minimal icon with recording state indicator
3. **Optional Visualization** - Full waveform popout for visual feedback

The key advantage over the GTK4 mic-osd is native integration with the QuickShell theme system (Colours, Appearance) and consistent styling with other bar widgets.
