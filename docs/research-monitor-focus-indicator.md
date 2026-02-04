# Research: Monitor Focus Indicator for Workspaces Pill

## Goal

Implement a visual indicator on the workspaces pill (center bar module) to show which monitor is currently focused. This helps users in multi-monitor setups quickly identify the active monitor.

## Proposed Visual Effects

### Option 1: Outer Glow (MultiEffect Shadow)
- Use `layer.enabled` with `MultiEffect` shadowEnabled
- Apply colored glow around the pill when monitor is focused
- **Status:** Tested, works but effect was not visually appealing

### Option 2: Enhanced Glassmorphism Intensity
- Increase glassmorphism intensity from `subtle` to `medium`/`strong` when focused
- **Status:** Attempted, encountered QML binding issues (see below)

### Option 3: Animated Border Color (Partially Working)
- Change border color to `m3primary` when focused
- Border width change from 1px to 2px
- **Status:** Border color animation WORKS correctly

## Technical Findings

### Monitor Focus Detection (Working)

```qml
// This binding correctly updates when focus changes between monitors
readonly property bool isMonitorFocused: Hypr.monitorFor(screen).focused
```

- `Hypr.monitorFor(screen).focused` returns a reactive boolean
- The `onIsMonitorFocusedChanged` signal fires correctly when switching monitors
- Each bar instance (one per monitor via `Variants` loop) has its own `screen` property

### QML Binding Issue with Glassmorphism Colors

**Problem:** When using ternary operators or conditional bindings with `Colours.glassmorphism()`, the color property doesn't update when `isMonitorFocused` changes.

**Observed Behavior:**
- `isMonitorFocused` changes correctly (debug logs confirm)
- `onColorChanged` signal fires, but both monitors show identical colors
- The same color value is logged for both `Focused: true` and `Focused: false`

**Attempted Solutions (None Worked for Background Color):**

1. **Direct ternary binding:**
   ```qml
   color: isMonitorFocused ? getFocusedBackground() : getUnfocusedBackground()
   ```
   Result: Color doesn't re-evaluate when focus changes

2. **Pre-computed readonly properties:**
   ```qml
   readonly property var glassStyleFocused: Colours.glassmorphism(...)
   readonly property var glassStyleUnfocused: Colours.glassmorphism(...)
   color: isMonitorFocused ? glassStyleFocused.background : glassStyleUnfocused.background
   ```
   Result: `readonly property var` evaluated once, doesn't re-evaluate

3. **Function calls in binding:**
   ```qml
   function getFocusedBackground(): color { return Colours.glassmorphism(...).background }
   color: { const _ = Colours.palette.m3surfaceContainerHigh; return isMonitorFocused ? getFocusedBackground() : getUnfocusedBackground() }
   ```
   Result: Still doesn't update

4. **Qt Binding type with `when` clause:**
   ```qml
   color: unfocusedBgColor
   Binding on color {
       when: root.isMonitorFocused
       value: root.focusedBgColor
       restoreMode: Binding.RestoreBindingOrValue
   }
   ```
   Result: Still doesn't work for glassmorphism-derived colors

**Why Border Color Works But Background Doesn't:**
- Border color uses direct palette color (`Colours.palette.m3primary`) - works fine
- Background color uses `Colours.glassmorphism(...).background` - doesn't react

### Suspected Root Cause

The `Colours.glassmorphism()` function likely has internal caching or the returned object's properties don't trigger QML's dependency tracking. This could be because:

1. The function returns a JavaScript object `{background: color, border: color}` that QML doesn't deeply track
2. The `Colours` service (singleton) may have some memoization
3. The glassmorphism calculation involves multiple steps that break the binding chain

### Resources

- [Qt Property Binding Documentation](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html)
- [Qt Binding Type with `when` clause](https://doc.qt.io/qt-6/qml-qtqml-binding.html)
- [KDAB: QML Engine Internals - Bindings](https://www.kdab.com/qml-engine-internals-part-2-bindings/)
- [Qt Forum: Property binding not updating](https://forum.qt.io/topic/18435/qml-property-binding-not-updating)

## What Works

### Border Color Animation
The border color change works perfectly:

```qml
border.color: glassStyle.border

Binding on border.color {
    when: root.isMonitorFocused
    value: Colours.palette.m3primary
    restoreMode: Binding.RestoreBindingOrValue
}

Behavior on border.color {
    ColorAnimation {
        duration: Appearance.anim.durations.normal
    }
}
```

## Future Implementation Ideas

### 1. Use Direct Colors Instead of Glassmorphism
Instead of calling `Colours.glassmorphism()`, compute the colors manually or use direct palette colors:

```qml
readonly property color focusedBgColor: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
readonly property color unfocusedBgColor: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)
```

### 2. Investigate Colours Service
Look into `services/Colours.qml` to understand how `glassmorphism()` works and whether it can be made more reactive.

### 3. Use State Machine
QML States might handle the transition more reliably:

```qml
states: [
    State {
        name: "focused"
        when: isMonitorFocused
        PropertyChanges { target: root; color: focusedBgColor }
    },
    State {
        name: "unfocused"
        when: !isMonitorFocused
        PropertyChanges { target: root; color: unfocusedBgColor }
    }
]
transitions: Transition {
    ColorAnimation { duration: 200 }
}
```

### 4. Just Use Border Color
Since border color works, a simple accent-colored border might be sufficient as a focus indicator without changing the background.

### 5. Alternative Visual Indicators
- Subtle scale change (1.02x when focused)
- Drop shadow appearance
- Animated underline/overline
- Icon brightness change

## Files Referenced

- `modules/bar/components/workspaces/Workspaces.qml` - Main workspaces component
- `services/Colours.qml` - Color/glassmorphism system
- `services/Hypr.qml` - Hyprland integration (monitor focus)
- `modules/drawers/Drawers.qml` - Per-monitor bar instantiation
