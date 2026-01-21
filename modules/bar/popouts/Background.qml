import qs.components
import qs.components.shapes
import qs.config

/// Bar popouts background using the reusable TopHangingBackground component.
///
/// Top-hanging panels descend from the bar with union corners at TL/TR.
/// Uses custom rounding that changes between attached (union with bar) and
/// detached (standalone floating panel) modes.
TopHangingBackground {
    // wrapper property inherited from TopHangingBackground
    // Detached popouts use smaller rounding; attached use Config.border.rounding
    customRounding: wrapper.isDetached ? Appearance.rounding.normal : Config.border.rounding
}
