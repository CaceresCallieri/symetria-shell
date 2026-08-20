import Quickshell.Io

JsonObject {
    property bool enabled: true
    property int hideDelay: 2000
    property bool enableBrightness: true
    property bool enableMicrophone: false

    /// Height of the right-edge hover strip that summons the OSD, in pixels.
    ///
    /// The strip is split in half at the screen's vertical centre: the upper
    /// half summons volume, the lower half brightness, and each card is centred
    /// in its own half so the OSD lands where the pointer already is. That makes
    /// the two a fixed destination you can reach without looking.
    ///
    /// ONE number drives both the trigger zones (Panels.qml) and the card
    /// offsets (OsdOverlay.qml), which are in different windows and cannot see
    /// each other's geometry. Do not add a second constant for the offset — the
    /// two would drift and the card would stop landing under the pointer, which
    /// is invisible when reading either file alone.
    property int triggerHeight: 320

    /// Width of that strip, in pixels, measured in from the right screen edge.
    ///
    /// MUST be greater than zero. The strip is not merely a hit test: Wrapper.qml
    /// builds one input Region per Panels child and subtracts it from the
    /// click-through mask, so a zero-width trigger produces a zero-width region
    /// and the pointer is never delivered there at all. The previous OSD trigger
    /// had implicitWidth 0 and could therefore never fire — it also made
    /// `panel.x` equal the screen width, so its own `x > panel.x` test was
    /// unsatisfiable. Both failures were invisible because nothing errors.
    ///
    /// Keep it narrow: these pixels stop belonging to the window underneath.
    property int triggerWidth: 5

    // NOTE: the former `sizes` block (sliderWidth / sliderHeight) was REMOVED,
    // not deprecated. The OSD has drawn a rotary dial rather than sliders since
    // the rotary rewrite, and the keys survived only because Panels.qml derived
    // the old hover band from sliderHeight. They now size nothing. A config key
    // that silently does nothing is worse than an absent one.
}
