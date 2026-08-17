pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// The entire lock screen UI: one password field and the feedback that field
// needs to be usable.
//
// This deliberately shows NOTHING else — no clock, no date, no avatar, no
// weather, no media, no notifications. The beams background is the subject; a
// grid of information panels competing with it was the old design.
//
// What survives is only what a person needs to get back in:
//   - how many characters they have typed
//   - whether an attempt is in flight (the submit button becomes the spinner)
//   - why an attempt failed
//   - caps lock / num lock / a non-default keyboard layout, which are the
//     classic reasons a correct password gets rejected
//
// Fingerprint still WORKS (see Pam.qml) but is no longer surfaced with an icon:
// it needs no affordance, since you either touch the reader or you don't. Its
// failures still surface through the message line below.
Item {
    id: root

    // Named `surface`, not `lock`: it holds the LockSurface, while Pam.qml uses
    // `lock` for the actual WlSessionLock. Two meanings of one word inside a
    // five-file module is how the wrong object gets passed.
    //
    // Left as `var` rather than typed `LockSurface` on purpose — LockSurface.qml
    // instantiates this file, so naming its type here would make the two files
    // circularly dependent, which QML's type compiler can reject outright.
    required property var surface
    readonly property Pam pam: surface.pam

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    // The lock surface has exclusive keyboard focus, but nothing inside it
    // competes for that focus, so grabbing it back unconditionally is safe and
    // guarantees keystrokes are never dropped on the floor.
    focus: true
    onActiveFocusChanged: {
        if (!activeFocus)
            forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (root.surface.unlocking)
            return;

        root.pam.handleKey(event);
    }

    ColumnLayout {
        id: column

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: field.visible ? (feedback.implicitHeight + spacing) / 2 : 0
        spacing: Appearance.spacing.large

        PillSurface {
            id: field

            // PAM clears the buffer as soon as it consumes the password, so
            // keep the pill around while the submit button is the spinner.
            visible: root.pam.buffer.length > 0 || root.pam.passwd.active

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Config.lock.sizes.fieldWidth
            implicitHeight: input.implicitHeight + Appearance.padding.small * 2

            StateLayer {
                // StateLayer defaults to `parent?.radius ?? 0`, but PillSurface
                // reparents its children into an inner holder Item that has no
                // radius — so the default would draw a SQUARE hover/ripple inside
                // a rounded pill. Bind the pill's own radius explicitly.
                radius: field.radius

                hoverEnabled: false
                cursorShape: Qt.IBeamCursor

                function onClicked(): void {
                    root.forceActiveFocus();
                }
            }

            RowLayout {
                id: input

                anchors.fill: parent
                anchors.margins: Appearance.padding.small
                spacing: Appearance.spacing.normal

                // Balance the submit slot so the password dots are centred on
                // the whole pill rather than on the space left beside it.
                Item {
                    implicitWidth: submit.implicitWidth
                    implicitHeight: 1
                }

                InputField {
                    pam: root.pam
                }

                // Submit button, which BECOMES the progress indicator while PAM
                // is checking. Same slot, same size, so nothing in the row
                // shifts on submit — and there is only one place to look for
                // "is something happening", instead of a spinner at one end and
                // the button you just pressed at the other.
                StyledRect {
                    // Explicit id rather than `parent.*` in the children below:
                    // `parent` is correct today because StyledRect is a plain
                    // Rectangle, but several containers in this codebase reparent
                    // their children into an inner holder, and this file already
                    // works around that once (see the StateLayer radius above).
                    id: submit

                    readonly property bool busy: root.pam.passwd.active
                    // Empty field reads as inert; a filled one reads as ready.
                    // While busy the button drops back to the container colour so
                    // the primary-coloured spinner on top of it stays legible.
                    readonly property bool armed: !busy && root.pam.buffer.length > 0

                    implicitWidth: implicitHeight
                    implicitHeight: enterIcon.implicitHeight + Appearance.padding.small * 2

                    // Armed takes the shell's ENGAGED treatment — the same
                    // polished accent metal as a connected network socket — via
                    // a lit finish rather than a raw m3primary fill. The raw
                    // fill was the last near-white blob left on the lock screen
                    // and read as a Material Design control sitting on a
                    // machined panel.
                    //
                    // Polished but NOT inset, unlike the socket or the ON switch
                    // knob. Those are engaged states: something IS connected,
                    // something IS on. This is a call to action — the key is lit
                    // and waiting, not depressed — so it keeps the raised
                    // silhouette and only takes the highlight.
                    readonly property var submitStyle: armed ? Colours.engagedAccent : Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

                    color: submitStyle.background
                    radius: Appearance.rounding.full
                    // The PILL role's border width, deliberately, in both states:
                    // this key keeps a raised silhouette even when armed, so it
                    // wants a display pill's edge. Only the FINISH switches to the
                    // engaged recipe. A material that wanted an edgeless armed key
                    // would express that by zeroing pill.borderWidth, which is the
                    // same lever every other raised plate in the shell answers to.
                    border.width: Theme.pill.borderWidth
                    border.color: submitStyle.border

                    SurfaceFinish {
                        anchors.fill: parent
                        radius: submit.radius
                        recipe: submit.armed ? Theme.engaged : Theme.pill
                    }

                    StateLayer {
                        // No re-submitting an attempt that is already in flight.
                        disabled: submit.busy
                        color: Colours.palette.m3onSurface

                        function onClicked(): void {
                            root.pam.passwd.start();
                        }
                    }

                    MaterialIcon {
                        id: enterIcon

                        anchors.centerIn: parent
                        text: "arrow_forward"
                        // One colour for both states: the armed body is now polished metal at
                        // lightness 0.400, and dark m3onPrimary (0.20) would have almost no
                        // contrast against it. The calendar's today cell hit the same trap
                        // and left a note about it; this is that note being applied.
                        color: Colours.palette.m3onSurface
                        font.weight: 500
                        opacity: submit.busy ? 0 : 1

                        Behavior on opacity {
                            Anim {}
                        }
                    }

                    CircularIndicator {
                        anchors.fill: parent
                        running: submit.busy
                        // Transparent track: the button's own fill is the
                        // background, so the indicator's default disc would
                        // stack a second circle on top of it.
                        bgColour: "transparent"
                    }
                }
            }
        }

        // Feedback slot. Both messages live in the same fixed-height row and
        // cross-fade, so the field above never shifts when one appears — a
        // password box that jumps while you are typing into it is unpleasant.
        Item {
            id: feedback

            Layout.fillWidth: true
            Layout.preferredWidth: field.implicitWidth

            implicitHeight: Math.max(message.implicitHeight, stateMessage.implicitHeight)

            Behavior on implicitHeight {
                Anim {}
            }

            // Keyboard-state hint. Suppressed while a real error is showing:
            // the active-lock icons are only a guess at why you failed, and
            // the actual PAM message is always the better answer.
            Item {
                id: stateMessage

                readonly property bool hasLayout: Hypr.kbLayout !== Hypr.defaultKbLayout
                readonly property bool active: field.visible && (Hypr.capsLock || Hypr.numLock || hasLayout)

                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: active ? keyboardStateRow.implicitHeight : 0

                scale: active && !message.msg ? 1 : 0.7
                opacity: active && !message.msg ? 1 : 0

                Row {
                    id: keyboardStateRow

                    anchors.centerIn: parent
                    spacing: Appearance.spacing.small

                    MaterialIcon {
                        visible: Hypr.capsLock
                        text: "keyboard_capslock_badge"
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    MaterialIcon {
                        visible: Hypr.numLock
                        text: "looks_one"
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        visible: stateMessage.hasLayout
                        text: qsTr("Keyboard layout: %1").arg(Hypr.kbLayoutFull)
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.small
                        font.family: Appearance.font.family.mono
                    }
                }

                Behavior on scale {
                    Anim {}
                }

                Behavior on opacity {
                    Anim {}
                }
            }

            StyledText {
                id: message

                readonly property Pam pam: root.pam
                readonly property string msg: {
                    if (pam.fprintState === "error")
                        return qsTr("FP ERROR: %1").arg(pam.fprint.message);
                    if (pam.state === "error")
                        return qsTr("PW ERROR: %1").arg(pam.passwd.message);

                    if (pam.lockMessage)
                        return pam.lockMessage;

                    if (pam.state === "max" && pam.fprintState === "max")
                        return qsTr("Maximum password and fingerprint attempts reached.");
                    if (pam.state === "max") {
                        if (pam.fprint.available)
                            return qsTr("Maximum password attempts reached. Please use fingerprint.");
                        return qsTr("Maximum password attempts reached.");
                    }
                    if (pam.fprintState === "max")
                        return qsTr("Maximum fingerprint attempts reached. Please use password.");

                    if (pam.state === "fail") {
                        if (pam.fprint.available)
                            return qsTr("Incorrect password. Please try again or use fingerprint.");
                        return qsTr("Incorrect password. Please try again.");
                    }
                    if (pam.fprintState === "fail")
                        return qsTr("Fingerprint not recognized (%1/%2). Please try again or use password.").arg(pam.fprint.tries).arg(Config.lock.maxFprintTries);

                    return "";
                }

                anchors.left: parent.left
                anchors.right: parent.right

                scale: 0.7
                opacity: 0
                color: Colours.palette.m3error

                font.pointSize: Appearance.font.size.small
                font.family: Appearance.font.family.mono
                horizontalAlignment: Qt.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere

                onMsgChanged: {
                    if (msg) {
                        if (opacity > 0) {
                            // `animate` drives StyledText's own text-change
                            // transition. It is switched off around the
                            // assignment because the flash below is the intended
                            // feedback — running both at once reads as a glitch.
                            animate = true;
                            text = msg;
                            animate = false;

                            exitAnim.stop();
                            if (scale < 1)
                                appearAnim.restart();
                            else
                                flashAnim.restart();
                        } else {
                            text = msg;
                            exitAnim.stop();
                            appearAnim.restart();
                        }
                    } else {
                        appearAnim.stop();
                        flashAnim.stop();
                        exitAnim.start();
                    }
                }

                // Repeating the SAME failure produces no msg change, so the
                // binding above would stay silent on a second wrong password.
                // This signal is what makes the message flash again.
                Connections {
                    target: root.pam

                    function onFlashMsg(): void {
                        exitAnim.stop();
                        if (message.scale < 1)
                            appearAnim.restart();
                        else
                            flashAnim.restart();
                    }
                }

                Anim {
                    id: appearAnim

                    target: message
                    properties: "scale,opacity"
                    to: 1
                    onFinished: flashAnim.restart()
                }

                SequentialAnimation {
                    id: flashAnim

                    loops: 2

                    FlashAnim {
                        to: 0.3
                    }
                    FlashAnim {
                        to: 1
                    }
                }

                ParallelAnimation {
                    id: exitAnim

                    Anim {
                        target: message
                        property: "scale"
                        to: 0.7
                        duration: Appearance.anim.durations.large
                    }
                    Anim {
                        target: message
                        property: "opacity"
                        to: 0
                        duration: Appearance.anim.durations.large
                    }
                }
            }
        }
    }

    component FlashAnim: NumberAnimation {
        target: message
        property: "opacity"
        duration: Appearance.anim.durations.small
        easing.type: Easing.Linear
    }
}
