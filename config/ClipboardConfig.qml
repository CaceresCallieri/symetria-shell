import Quickshell.Io

JsonObject {
    property bool enabled: true
    property bool showOnHover: false
    property int maxShown: 1000        // Maximum entries to load from cliphist
    property int maxDisplayed: 10      // Entries shown without search query
    property int maxImagesDisplayed: 6 // 2x3 grid fits drawer without scrolling
    property int previewLength: 80
    property int dragThreshold: 50
    property bool useFuzzy: false      // false=FZF (fast), true=Fuzzysort (tolerates typos)
    property int clearConfirmTimeout: 2000  // ms - time before clear confirmation resets
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int itemWidth: 500
        property int itemHeight: 48
    }
}
