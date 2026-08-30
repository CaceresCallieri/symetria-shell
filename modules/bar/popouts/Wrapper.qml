pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import qs.modules.windowinfo as WindowInfoModule
import qs.modules.controlcenter as ControlCenterModule
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

Item {
    id: root

    required property ShellScreen screen

    readonly property real nonAnimWidth: children.find(c => c.shouldBeActive)?.implicitWidth ?? content.implicitWidth
    readonly property real nonAnimHeight: y > 0 || hasCurrent || isDetached ? children.find(c => c.shouldBeActive)?.implicitHeight ?? content.implicitHeight : 0
    readonly property Item current: content.item?.current ?? null

    property string currentName
    property real currentCenter
    property bool hasCurrent
    property bool keyboardNavigationActive: false

    onHasCurrentChanged: {
        if (!hasCurrent)
            keyboardNavigationActive = false;
    }

    property string detachedMode
    property string queuedMode
    readonly property bool isDetached: detachedMode.length > 0

    property int animLength: Appearance.anim.durations.normal
    property list<real> animCurve: Appearance.anim.curves.emphasized

    // When true, the Wrapper fills its parent and disables all Behaviors so
    // detached panels (controlcenter, windowinfo) can center + scale/fade
    // without interference from the bar-popout size/position animation system.
    readonly property bool _detachedFull: isDetached || _closingFromDetached
    // Briefly true during open/close transitions to prevent Behaviors from
    // animating stale → new values during the binding switchover.
    property bool _suppressAnim: false
    property int _suppressGeneration: 0
    // Stays true during the close fade-out so the Wrapper keeps its full size
    // until the DetachedComp animation finishes.
    property bool _closingFromDetached: false

    function detach(mode: string): void {
        _closingTimer.stop();
        _closingFromDetached = false;
        _suppressGeneration++;
        const gen = _suppressGeneration;
        _suppressAnim = true;
        if (mode === "winfo") {
            detachedMode = mode;
        } else {
            detachedMode = "any";
            queuedMode = mode;
        }
        focus = true;
        Qt.callLater(() => { if (_suppressGeneration === gen) _suppressAnim = false; });
    }

    function close(): void {
        const wasDetached = isDetached;
        // `gen` is computed at FUNCTION scope, before the blocks that use it:
        // the release callback at the bottom of this function reads it from a
        // second `if (wasDetached)` block. Declaring it inside the first block
        // threw "ReferenceError: gen is not defined" on every detached close, so
        // the early release never ran and _suppressAnim stayed set until
        // _closingTimer fired. Mirrors detach(), which gets this right.
        const gen = wasDetached ? ++_suppressGeneration : 0;
        if (wasDetached) {
            _closingFromDetached = true;
            _suppressAnim = true;
            _closingTimer.start();
        }
        hasCurrent = false;
        keyboardNavigationActive = false;
        animLength = Appearance.anim.durations.normal;
        detachedMode = "";
        queuedMode = "";
        animCurve = Appearance.anim.curves.emphasized;
        if (wasDetached) {
            Qt.callLater(() => { if (_suppressGeneration === gen) _suppressAnim = false; });
        }
    }

    // Cleans up _closingFromDetached after the DetachedComp's fade-out
    // animation has finished, then snaps the Wrapper back to zero size.
    Timer {
        id: _closingTimer

        interval: Appearance.anim.durations.small
        onTriggered: {
            root._suppressGeneration++;
            const gen = root._suppressGeneration;
            root._suppressAnim = true;
            root._closingFromDetached = false;
            Qt.callLater(() => { if (root._suppressGeneration === gen) root._suppressAnim = false; });
        }
    }

    visible: _detachedFull || (width > 0 && height > 0)
    // Bar popouts need clipping for the height-reveal animation.
    // Detached panels fill the parent, so clipping would hide content
    // that overflows the Wrapper during async loading.
    clip: !_detachedFull

    // When detached, fill the parent so centered content positions correctly.
    // When in bar-popout mode, size to content for the reveal animation.
    implicitWidth: _detachedFull ? (parent?.width ?? nonAnimWidth) : nonAnimWidth
    implicitHeight: _detachedFull ? (parent?.height ?? nonAnimHeight) : nonAnimHeight

    focus: hasCurrent
    Keys.onEscapePressed: {
        // Forward escape to password popout if active, otherwise close
        if (currentName === "wirelesspassword" && content.item) {
            const passwordPopout = content.item.children.find(c => c.name === "wirelesspassword");
            if (passwordPopout && passwordPopout.item) {
                passwordPopout.item.closeDialog();
                return;
            }
        }
        // Cancel the pending update process when Escape is pressed during password entry —
        // the process is blocked on stdin and must not linger after the popout closes.
        if (_updatesPasswordActive) {
            UpdateRunner.cancel();
        }
        close();
    }

    Keys.onPressed: event => {
        // Don't intercept keys when password popout is active - let it handle them
        if (currentName === "wirelesspassword") {
            event.accepted = false;
        }
    }

    // Grab is active for detached panels (controlcenter, winfo). It used to
    // cover the STT recording popout too, whose vocab-hints TextField lived in
    // THIS window; that popout went out with the merged agent bar, and the
    // drawer's own vocab-hints surface has the drawer window's grab.
    //
    // The updates popout's sudo password field lives in THIS window, so it
    // needs the same grab treatment as the vocab hints input: without the grab
    // the compositor never routes keys here until the user clicks the field.
    readonly property bool _updatesPasswordActive: root.hasCurrent
        && root.currentName === "updates"
        && UpdateRunner.phase === "password"

    HyprlandFocusGrab {
        active: root.isDetached || (root.keyboardNavigationActive && root.hasCurrent) || root._updatesPasswordActive
        windows: [QsWindow.window]
        onCleared: {
            if (root._updatesPasswordActive) {
                // Click-outside during password entry abandons the pending run —
                // the process is blocked on stdin and must not linger.
                UpdateRunner.cancel();
                root.close();
            } else
                root.close();
        }
    }

    Binding {
        when: root.isDetached

        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    Binding {
        when: root.hasCurrent && (root.keyboardNavigationActive || root.currentName === "wirelesspassword")

        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    // Keyboard focus for the updates popout while it shows the sudo password field.
    Binding {
        when: root._updatesPasswordActive

        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    Comp {
        id: content

        shouldBeActive: root.hasCurrent && !root.detachedMode
        asynchronous: true
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: Content {
            wrapper: root
        }
    }

    DetachedComp {
        shouldBeActive: root.detachedMode === "winfo"
        asynchronous: true
        anchors.centerIn: parent

        sourceComponent: WindowInfoModule.Wrapper {
            screen: root.screen
            client: Hypr.activeToplevel
        }
    }

    DetachedComp {
        shouldBeActive: root.detachedMode === "any"
        asynchronous: true
        anchors.centerIn: parent

        sourceComponent: ControlCenterModule.Wrapper {
            screen: root.screen
            active: root.queuedMode

            function close(): void {
                root.close();
            }
        }
    }

    // --- Behaviors: only active for bar-popout mode ---

    // Note: unlike y/implicitWidth/implicitHeight, the x Behavior intentionally
    // omits the `implicitHeight > 0` guard — the slide-to-icon animation on
    // first hover-open is part of the upstream design.
    Behavior on x {
        enabled: !root._detachedFull && !root._suppressAnim

        Anim {
            duration: root.animLength
            easing.bezierCurve: root.animCurve
        }
    }

    Behavior on y {
        enabled: root.implicitHeight > 0 && !root._detachedFull && !root._suppressAnim

        Anim {
            duration: root.animLength
            easing.bezierCurve: root.animCurve
        }
    }

    Behavior on implicitWidth {
        enabled: root.implicitHeight > 0 && !root._detachedFull && !root._suppressAnim

        Anim {
            duration: root.animLength
            easing.bezierCurve: root.animCurve
        }
    }

    Behavior on implicitHeight {
        enabled: !root._detachedFull && !root._suppressAnim

        Anim {
            duration: root.animLength
            easing.bezierCurve: root.animCurve
        }
    }

    // --- Bar-popout loader: opacity-only transitions ---

    component Comp: Loader {
        id: comp

        property bool shouldBeActive

        asynchronous: true
        active: false
        opacity: 0

        states: State {
            name: "active"
            when: comp.shouldBeActive

            PropertyChanges {
                comp.opacity: 1
                comp.active: true
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        property: "opacity"
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        property: "opacity"
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }

    // --- Detached-panel loader: scale + opacity collapse animation ---
    // Mirrors the keychords overlay pattern (Overlay.qml) — the content
    // scales from 0.9→1.0 with a subtle OutBack bounce on open and
    // collapses back with InBack easing on close.

    component DetachedComp: Loader {
        id: dcomp

        property bool shouldBeActive

        asynchronous: true
        active: false
        opacity: 0
        scale: 0.9
        transformOrigin: Item.Center

        states: State {
            name: "active"
            when: dcomp.shouldBeActive

            PropertyChanges {
                dcomp.opacity: 1
                dcomp.active: true
                dcomp.scale: 1
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    ParallelAnimation {
                        Anim {
                            property: "opacity"
                        }
                        NumberAnimation {
                            property: "scale"
                            duration: Appearance.anim.durations.normal
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    ParallelAnimation {
                        Anim {
                            property: "opacity"
                            duration: Appearance.anim.durations.small
                        }
                        NumberAnimation {
                            property: "scale"
                            duration: Appearance.anim.durations.small
                            easing.type: Easing.InBack
                        }
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }
}
