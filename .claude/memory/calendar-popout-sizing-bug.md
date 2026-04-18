# Calendar Popout Sizing Bug — Full Debug Knowledge

**Status: OPEN — Non-deterministic, reduced frequency but not eliminated.**
**Severity: Low (usable, cosmetic issue ~20-30% of the time)**

## Feature Context

A calendar popout was added to the TimePill in the bar. It reuses the dashboard's `Dash.Calendar` component (`modules/dashboard/dash/Calendar.qml`). The popout opens on hover over the date or clock items in the TimePill.

### Files Involved

| File | Role |
|------|------|
| `modules/bar/popouts/Calendar.qml` | Popout wrapper around Dash.Calendar |
| `modules/bar/popouts/Content.qml` | Registers `"calendar"` popout (line ~123) |
| `modules/bar/Bar.qml` | Maps `"date"`/`"clock"` → `"calendar"` in TimePill name resolver (line ~218) |
| `config/BarConfig.qml` | `calendarWidth: 300` in Sizes (line ~138) |
| `modules/dashboard/dash/Calendar.qml` | The reused calendar component (MODIFIED — see below) |

## The Bug: Non-Deterministic Calendar Sizing

The calendar popout renders with **compressed row spacing** approximately 20-30% of the time. The correct appearance has evenly-spaced rows; the broken appearance has tightly-packed rows.

### Correct vs Broken Appearance

- **Correct**: All rows evenly spaced, proper padding, implicitHeight = 253
- **Broken (mild)**: Rows slightly compressed, implicitHeight ~176-202
- **Broken (severe)**: Rows very tightly packed, implicitHeight ~79-149

## Root Cause Analysis

### Primary: MonthGrid Asynchronous Delegate Creation

**MonthGrid creates its 42 delegates (6 weeks × 7 days) asynchronously across multiple frames.** The delegate `implicitHeight` values are not available immediately. At any given moment during creation:

| Delegates Ready | Approximate implicitHeight |
|-----------------|---------------------------|
| ~1-2 rows | 79 |
| ~3-4 rows | 149 |
| ~4-5 rows | 176-202 |
| All 6 rows | **253 (correct)** |

### Secondary: Popout Loader Destroy/Recreate Cycle

Each hover-in creates the Calendar fresh (`Loader.active = true`), each hover-out destroys it. MonthGrid must create all 42 delegates from scratch every time. There is no caching across popout activations.

### Qt Source Code Analysis (MonthGrid Internals)

From [QQuickMonthGrid source](https://codebrowser.dev/qt6/qtdeclarative/src/quicktemplates/qquickmonthgrid.cpp.html):

- `resizeItems()` distributes space **top-down**: `cellHeight = (contentItem.height - 5*spacing) / 6`
- Called from `componentComplete()`, `geometryChange()`, `updatePolish()` — layout is deferred through Qt's polish mechanism
- MonthGrid inherits from [QQuickControl](https://doc.qt.io/Qt-6/qml-qtquick-controls-control.html): `implicitHeight = max(background + insets, implicitContentHeight + padding)`
- `implicitContentHeight = contentItem.implicitHeight` — depends on delegates being created
- No `populated` signal, no `forceLayout()`, no `cacheBuffer`, no way to force synchronous delegate creation from QML

### Why the Dashboard Calendar Works Fine

In `modules/dashboard/Dash.qml`:
```qml
Rect {
    Layout.preferredHeight: calendar.implicitHeight  // GridLayout sets Rect.height
    Calendar { state: root.state }                   // Calendar.anchors.left/right → Rect
}
```

The dashboard Calendar is created **once** at shell startup (not destroyed/recreated on each view). By the time the user sees the dashboard, all 42 delegates have long since been created. The popout suffers because it recreates the Calendar fresh on every hover.

### Dash.Calendar Internal Structure

```qml
// modules/dashboard/dash/Calendar.qml (MODIFIED in this session)
CustomMouseArea {  // extends MouseArea extends Item
    anchors.left: parent.left
    anchors.right: parent.right
    // NO explicit height — defaults to 0
    implicitWidth: inner.implicitWidth + inner.anchors.margins * 2
    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2

    ColumnLayout {
        id: inner
        // CHANGED from `anchors.fill: parent` to left/right/top only
        // This breaks the circular dependency: Calendar.height no longer
        // affects ColumnLayout.height, so implicitHeight is independent.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Appearance.padding.large
        spacing: Appearance.spacing.small

        RowLayout { ... }             // Month navigation (< March 2026 >)
        DayOfWeekRow { ... }          // Sun Mon Tue Wed Thu Fri Sat
        Item {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight

            MonthGrid {
                id: grid
                anchors.fill: parent  // Fills the Item wrapper
                spacing: 3
                delegate: Item {
                    implicitWidth: implicitHeight  // Square cells
                    implicitHeight: text.implicitHeight + padding
                }
            }
        }
    }
}
```

### The `anchors.fill` Fix (Partial Success)

**Original problem:** `ColumnLayout { anchors.fill: parent }` created a circular dependency:
```
Calendar.height → ColumnLayout.height (anchors.fill) → layout distributes space →
inner.implicitHeight → Calendar.implicitHeight → (if bound) Calendar.height
```

**Fix applied:** Changed to `anchors.left/right/top` only. This means ColumnLayout sizes itself naturally (height = implicitHeight from children), independent of Calendar.height. Removed the feedback loop.

**Result:** Reduced frequency of the bug significantly (from ~50% to ~20-30%), but did NOT eliminate it. The remaining failures are purely from MonthGrid's async delegate creation — the implicitHeight is simply wrong until all delegates exist.

## Current State of Code

### modules/bar/popouts/Calendar.qml (current — clean, no hacks)
```qml
pragma ComponentBehavior: Bound

import qs.modules.dashboard.dash as Dash
import qs.config
import QtQuick

Item {
    id: root
    width: Config.bar.sizes.calendarWidth

    QtObject {
        id: calendarState
        property date currentDate: new Date()
    }

    Dash.Calendar {
        id: calendar
        state: calendarState
    }

    implicitWidth: width
    implicitHeight: calendar.implicitHeight
}
```

### modules/dashboard/dash/Calendar.qml (modified — anchors change)
```diff
 ColumnLayout {
     id: inner
-    anchors.fill: parent
+    anchors.left: parent.left
+    anchors.right: parent.right
+    anchors.top: parent.top
     anchors.margins: Appearance.padding.large
     spacing: Appearance.spacing.small
```

## All Approaches Tried

### 1. `height: implicitHeight` binding (FAILED — oscillation)
Creates a binding feedback loop through `anchors.fill`. Oscillates and converges to wrong value.
```
implicitHeight: 79 → 97 → 201 → 167 → 144 → 129 → ... → 99 → 176 (STUCK)
```

### 2. No explicit height, height=0 (FAILED — visual compression)
ColumnLayout compresses children to 0. Visually broken.

### 3. Timer(interval=0) one-shot assignment (FAILED — too early)
Fires before delegates or even anchors are ready. `ih=18, w=18` or `ih=79, w=300`.

### 4. Generous height=400 + Timer(interval=50ms) (FAILED — race condition)
50ms isn't always enough for MonthGrid to create all 42 delegates.

### 5. Polling Timer 16ms, 3 stable frames (FAILED — delegates load in batches)
MonthGrid creates delegates in batches with pauses between them. implicitHeight can be stable at a wrong value (e.g., 79) for >3 frames before jumping to the next batch value.

### 6. Remove `anchors.fill` → `anchors.left/right/top` (PARTIAL — current state)
Breaks the circular dependency. ColumnLayout sizes independently. Reduced frequency from ~50% to ~20-30%. Remaining failures are purely from async delegate creation timing — no workaround found from QML side.

## Evidence from Debug Logs

**With `height: implicitHeight` binding (BINDING LOOP):**
```
Calendar.height → inner.height (anchors.fill) → inner.implicitHeight → Calendar.implicitHeight → Calendar.height
```

**With generous initial height=400 and Timer(interval=50ms):**
```
Timer: locked height=149 (ih=149, w=300)  ← partial delegates
Timer: locked height=176 (ih=176, w=300)  ← partial delegates
Timer: locked height=253 (ih=253, w=300)  ← correct
Timer: locked height=202 (ih=202, w=300)  ← partial delegates
Timer: locked height=253 (ih=253, w=300)  ← correct
```

**Initialization Sequence (from debug logs):**
1. Calendar.width starts at **18** (Calendar.implicitWidth before anchors resolve)
2. Calendar.width jumps to **170 or 218** (intermediate, varies non-deterministically)
3. Calendar.width reaches **300** (final, from anchors.left/right → wrapper)
4. Calendar.implicitHeight starts at **18** (corresponds to initial 18px width)
5. Calendar.implicitHeight may settle at **79, 149, 176, 202, or 253** depending on how many MonthGrid delegates are ready

## Potential Future Approaches (NOT tried)

### A. Binding with `delayed: true`
```qml
Binding { target: calendar; property: "height"; value: calendar.implicitHeight; delayed: true }
```
[Qt docs](https://doc.qt.io/qt-6/qml-qtqml-binding.html): Defers binding updates to end of event loop. Might break oscillation across frames. Risk: might still produce wrong values if delegates aren't ready.

### B. `onImplicitHeightChanged` ratchet with generous initial height
```qml
Dash.Calendar {
    height: 400
    property real maxIh: 0
    onImplicitHeightChanged: {
        if (implicitHeight > maxIh) {
            maxIh = implicitHeight;
            Qt.callLater(() => { calendar.height = calendar.maxIh; });
        }
    }
}
```
Only increases height as delegates load. Qt.callLater defers to avoid sync feedback. Wrapper uses `implicitHeight: calendar.maxIh`. Risk: if implicitHeight spikes above correct value, locks wrong.

### C. Create dedicated popout calendar (ROBUST — code duplication)
Copy Dash.Calendar's content into the popout, replacing internal structure to avoid `anchors.fill` and using a ColumnLayout that sizes naturally. ~250 lines of duplication but guaranteed correct sizing.

### D. Keep Calendar alive across popout cycles
Instead of using the Popout Loader (which destroys/recreates on each hover), keep the Calendar component alive and just show/hide it. MonthGrid delegates would only be created once. Requires changes to the Popout system in Content.qml — possibly set `Popout.active: true` permanently for the calendar popout and control visibility separately.

**This is likely the most promising approach** since it directly addresses the root cause (repeated delegate creation).

### E. Force synchronous delegate creation from C++ plugin
Extend the Symmetria C++ plugin to provide a custom calendar grid that creates delegates synchronously. Heavy-handed but would guarantee correct sizing.

### F. Qt.callLater chain for implicitHeight propagation
```qml
Dash.Calendar {
    id: calendar
    state: calendarState
    onImplicitHeightChanged: Qt.callLater(() => root.implicitHeight = calendar.implicitHeight)
}
```
Defer the implicitHeight propagation to the popout wrapper. The popout might render at wrong size for 1 frame, then correct itself. Risk: visible "jump" in popout size.

### G. Pre-warm the Calendar (keep a hidden instance)
Create a permanently-alive hidden Calendar instance that pre-creates all MonthGrid delegates. When the popout opens, read the correct implicitHeight from the hidden instance and apply it to the visible one. Complex but avoids async issues.

## Key Constants

| Value | Meaning |
|-------|---------|
| 300 | `Config.bar.sizes.calendarWidth` (wrapper width) |
| 253 | Correct `calendar.implicitHeight` at width=300 |
| 235 | Correct inner ColumnLayout `implicitHeight` (253 - 2 × Appearance.padding.large) |
| 18 | 2 × Appearance.padding.large (margins, also Calendar's initial implicitHeight before anchors resolve) |
| 79 | Wrong implicitHeight when MonthGrid has ~1-2 rows of delegates |

## Popout System Architecture (for context)

The Popout in `Content.qml` is a `Loader` component:
```qml
component Popout: Loader {
    required property string name
    readonly property bool shouldBeActive: root.wrapper.currentName === name
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    opacity: 0; scale: 0.8; active: false

    // When shouldBeActive: active→true, then animate opacity/scale to 1
    // When deactivated: animate out, then active→false (destroys content)
}
```

Each hover-in creates the component (Loader.active = true), each hover-out destroys it. The Popout reads `implicitWidth`/`implicitHeight` from the loaded component.

The parent `Content` item sizes itself:
```qml
implicitWidth: (currentPopout?.implicitWidth ?? 0) + Appearance.padding.large * 2
implicitHeight: (currentPopout?.implicitHeight ?? 0) + Appearance.padding.large * 2
```

Other popout components (Weather, Updates, Ram) set `width: Config.bar.sizes.xxxWidth` and rely on natural implicit height from their Column/layout children. None have this timing issue because they use static content, not delegates.
