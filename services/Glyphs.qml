pragma Singleton

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

// The Phosphor glyph fonts and the names they cover. Read by exactly one
// consumer, components/MaterialIcon.qml; nothing else should pick an icon font.
//
// The fonts in assets/glyphs answer to Material Symbols NAMES through
// ligatures, so a MaterialIcon keeps its `text` ("volume_up") and changes only
// its font family. How they are built, and why QML reads glyph-names.json
// rather than glyph-map.json, is in scripts/build-glyph-fonts.py.
//
// A name the fonts do not cover draws in Material Symbols instead, and is
// reported once in the shell log. To cover it, add it to
// assets/glyphs/glyph-map.json and run scripts/build-glyph-fonts.py; editing
// the map alone changes nothing.
Singleton {
    id: root

    // Covered names as a lookup object. Plain writable: the FileView handler
    // assigns it (see the readonly pitfall in docs/qml-pitfalls.md).
    property var _covered: ({})
    property bool _namesLoaded: false

    // Names already reported as missing. A JS Set rather than a property, so
    // recording a report from inside covers() never re-triggers a binding.
    readonly property var _reported: new Set()

    readonly property bool _fontsReady: lightFont.status === FontLoader.Ready && fillFont.status === FontLoader.Ready
    // False while Theme.glyphs is "material" and until both fonts and the name
    // list have loaded; MaterialIcon draws Material Symbols in the meantime.
    readonly property bool active: Theme.glyphs === "phosphor" && _fontsReady && _namesLoaded

    // Whether the active glyph family draws `name`. False under Material.
    function covers(name: string): bool {
        if (!active)
            return false;
        if (root._covered[name] === true)
            return true;
        _reportMissing(name);
        return false;
    }

    // Phosphor has no fill axis, only a separate Fill weight, so a MaterialIcon's
    // `fill` becomes a choice of font. An animated fill flips at the midpoint.
    function familyFor(fill: real): string {
        return fill >= 0.5 ? fillFont.name : lightFont.name;
    }

    function _reportMissing(name: string): void {
        // Numbers and empty strings pass through MaterialIcon too (FilledSlider
        // shows its value in one); only something shaped like a name is a gap.
        if (!/^[a-z][a-z0-9_]*$/.test(name) || root._reported.has(name))
            return;
        root._reported.add(name);
        console.warn(`Glyphs: no Phosphor glyph for "${name}", drawing Material Symbols. Add it to assets/glyphs/glyph-map.json and run scripts/build-glyph-fonts.py.`);
    }

    FontLoader {
        id: lightFont

        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/glyphs/SymmetriaPhosphor-Light.ttf`)
    }

    FontLoader {
        id: fillFont

        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/glyphs/SymmetriaPhosphor-Fill.ttf`)
    }

    FileView {
        path: `${Quickshell.shellDir}/assets/glyphs/glyph-names.json`
        onLoaded: {
            const covered = {};
            for (const name of JSON.parse(text()).names)
                covered[name] = true;
            root._covered = covered;
            root._namesLoaded = true;
        }
    }
}
