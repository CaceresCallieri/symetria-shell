import qs.components.shapes

/// Naming shim: re-exports TopHangingBackground as SttBackground to avoid a
/// type name collision with Background.qml files in other modules (e.g.,
/// drawers/Backgrounds.qml).  See CLAUDE.md > QML Type Naming Convention.
///
/// Top-hanging panels descend from the bar with union corners at TL/TR
/// that blend smoothly with the bar/border.
TopHangingBackground {
}
