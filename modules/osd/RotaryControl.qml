pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.config
import QtQuick

/// Value plumbing shared by every OSD dial (RotaryKnob, BrightnessIris).
///
/// Owns the normalisation, the eased `animatedValue` that visuals bind to, the
/// wheel and drag interaction, and the angle-to-value mapping. A dial file
/// supplies ONLY its visuals as children and must not re-implement any of this:
/// the drag geometry in particular (the 270° sweep starting at -135°, and the
/// dead zone at the bottom of the circle) has to stay identical across dials, or
/// the same drag gesture means different values depending on which OSD is up.
///
/// Children are authored in a `designSize`-unit space and multiplied by
/// `sizeScale`, so one scale number means the same physical size in every dial.
/// Convert a design unit to a pixel with `u(n)`.
Item {
    id: root

    /// The dial's visuals. Rendered below the hit area, in declaration order.
    ///
    /// Children are REPARENTED into the internal `visuals` Item, so `parent`
    /// inside a dial file means `visuals`, not this control. That is invisible
    /// today only because `visuals` is `anchors.fill: parent` with no margins —
    /// give it padding and every dial's geometry silently shifts.
    default property alias content: visuals.data

    required property real value
    required property real to
    property real sizeScale: 1

    /// Design-space width of the draggable centre. Anything outside it is
    /// decoration and does not take the press — matching a real panel control,
    /// where you grab the knob and not the scale printed around it.
    property real hitSize: 116

    signal moved(real value)
    signal wheelMoved(real delta)

    readonly property real designSize: 176

    function u(n: real): real {
        return n * sizeScale;
    }

    /// A point on a circle around the dial's centre, in the degree convention the
    /// dials use throughout: 0 is right, and the angle rises clockwise because
    /// screen y grows downward. `radius` is in pixels, so pass it through `u()`.
    ///
    /// Exists so that a shape which must close on exactly the point it started
    /// from can derive both from one expression. BrightnessIris lost a whole blade
    /// for a frame when two spellings of the same corner disagreed by a float
    /// epsilon — see the note above its blade Shape.
    function polarX(angle: real, radius: real): real {
        return width / 2 + radius * Math.cos(angle * Math.PI / 180);
    }

    function polarY(angle: real, radius: real): real {
        return height / 2 + radius * Math.sin(angle * Math.PI / 180);
    }

    readonly property real normalizedValue: Math.max(0, Math.min(1, value / Math.max(to, 0.001)))
    readonly property bool interacting: interaction.pressed || wheelInteractionTimer.running
    property real animatedValue: normalizedValue

    implicitWidth: Math.round(designSize * sizeScale)
    implicitHeight: Math.round(designSize * sizeScale)

    Behavior on animatedValue {
        Anim {
            duration: Appearance.anim.durations.expressiveFastSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveEffects
        }
    }

    Item {
        id: visuals

        anchors.fill: parent
    }

    CustomMouseArea {
        id: interaction

        anchors.centerIn: parent
        width: Math.round(root.hitSize * root.sizeScale)
        height: width
        cursorShape: Qt.PointingHandCursor

        function onWheel(event: WheelEvent): void {
            wheelInteractionTimer.restart();
            root.wheelMoved(event.angleDelta.y);
        }

        function updateValue(x: real, y: real): void {
            const centre = width / 2;
            let angle = Math.atan2(y - centre, x - centre) * 180 / Math.PI;
            // Bottom wedge is the gap in the scale: snap to whichever end is nearer
            // rather than letting the value jump across it mid-drag.
            if (angle > 45 && angle < 135) {
                root.moved((angle < 90 ? 1 : 0) * root.to);
                return;
            }
            if (angle < 135)
                angle += 360;
            const normalized = Math.max(0, Math.min(1, (angle - 135) / 270));
            root.moved(normalized * root.to);
        }

        // The hit area is a square but every dial is a disc, so a press in a
        // corner would map an angle from a point over visibly empty recess and
        // jump the value. Rejected presses do not start a drag at all.
        //
        // Only the PRESS is guarded — onPositionChanged deliberately is not, so
        // that once a drag has started it keeps tracking when the pointer leaves
        // the disc, which is how a real knob behaves under the finger.
        onPressed: event => {
            if (Math.hypot(event.x - width / 2, event.y - height / 2) > width / 2) {
                event.accepted = false;
                return;
            }
            updateValue(event.x, event.y);
        }
        onPositionChanged: event => {
            if (pressed)
                updateValue(event.x, event.y);
        }
    }

    Timer {
        id: wheelInteractionTimer

        // How long a wheel gesture keeps `interacting` true. It spans the gap
        // between notches of one scroll, so a burst does not read as several
        // separate interactions — and, because OsdOverlay gates metric switching
        // on `interacting`, so another metric cannot steal the OSD mid-scroll.
        interval: 180
    }
}
