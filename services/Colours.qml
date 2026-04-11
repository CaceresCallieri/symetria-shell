pragma Singleton
pragma ComponentBehavior: Bound

import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ═══════════════════════════════════════════════════════════════════════════
    // UNIFIED BACKGROUND TINT - Change this ONE value to customize all backgrounds
    // ═══════════════════════════════════════════════════════════════════════════
    readonly property color panelBackgroundTint: "#000000"
    readonly property real panelBackgroundAlpha: 1.0

    // Derived properties - these automatically update when panelBackgroundTint changes
    // Legacy: Use for isolated components where overlap is impossible
    readonly property color generalBackground: Qt.alpha(panelBackgroundTint, panelBackgroundAlpha)

    // Layer-based transparency: Use when multiple shapes may overlap
    // Container applies transparency via layer.enabled + opacity, preventing
    // double-opacity artifacts where shapes would otherwise compound alpha
    readonly property color generalBackgroundOpaque: panelBackgroundTint
    readonly property real generalBackgroundAlpha: panelBackgroundAlpha

    property list<string> _paletteKeys: []

    // Absolute path to the bundled default scheme (used to seed state file on first launch)
    // string (not url): raw filesystem path passed to shell cp — not a QML source URL
    readonly property string _defaultSchemePath: Qt.resolvedUrl("../config/color-scheme.json").toString().replace(/^file:\/\//, "")
    readonly property bool light: false
    readonly property M3Palette palette: current
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = 0.3 * (1 - transparency.base) * (1 + wallLuminance * 2.5);
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    // intentional var: nullable — callers pass integers 0–3 and null (which defaults to 1 via ?? operator)
    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    // Glassmorphism constants - tuned for visual coherence across intensity levels
    readonly property QtObject glassConstants: QtObject {
        // Maximum layer depth for most subtle glass (intensity = 0)
        // Higher values = darker/more transparent background
        readonly property real maxLayerDepth: 3

        // Layer depth reduction per intensity unit
        // Formula: layerDepth = maxLayerDepth - (intensity * depthRange)
        readonly property real depthRange: 2

        // Border brightness ratio relative to background layer depth
        // 0.2 = border uses 20% of background's layer depth (80% brighter)
        readonly property real borderBrightnessRatio: 0.2

        // Border opacity adjustment after layering
        // 0.35 provides subtle glass edge across all intensities
        readonly property real borderOpacity: 0.35

        // Border base color: pure white for dark mode
        readonly property color borderBaseColor: "#ffffff"
    }

    // Glassmorphism helper: returns consistent background + border colors
    //
    // @param baseColor: M3 palette color for glass base (e.g., m3surfaceContainerHigh, m3primary)
    // @param intensity: Glass brightness from 0 (subtle/dark) to 1 (strong/bright)
    // @returns: { background: color, border: color }
    //
    // Design: Background and border scale proportionally maintaining visual relationship
    function glassmorphism(baseColor: color, intensity: real): var {
        // Clamp intensity to valid range [0, 1]
        const clampedIntensity = Math.max(0, Math.min(1, intensity));

        // Calculate layer depths
        const layerDepth = glassConstants.maxLayerDepth - (clampedIntensity * glassConstants.depthRange);
        const borderLayerDepth = layerDepth * glassConstants.borderBrightnessRatio;

        // Apply layering system
        const backgroundColor = layer(baseColor, layerDepth);
        const borderColor = Qt.alpha(layer(glassConstants.borderBaseColor, borderLayerDepth), glassConstants.borderOpacity);

        return {
            background: backgroundColor,
            border: borderColor
        };
    }

    // Matte pill constants — refined dark aesthetic with subtle white edge
    readonly property QtObject matteConstants: QtObject {
        // Dark charcoal base lightness (fully opaque)
        readonly property real baseLightness: 0.10

        // How much intensity brightens the background
        readonly property real lightnessRange: 0.08

        // Saturation fraction of baseColor applied to background (0 = pure grey, higher = more palette tinting)
        readonly property real colorTint: 0.12

        // Border base color — pure white is chromatically neutral,
        // works with any M3 palette and reads as a subtle light edge
        readonly property color borderColor: "#ffffff"

        // Border opacity — barely perceptible edge definition
        // (0.12 = just enough to separate pill from background)
        readonly property real borderOpacity: 0.12
    }

    // Matte pill helper: returns opaque dark background + subtle white border
    //
    // @param baseColor: M3 palette color for hue tinting (e.g., m3surfaceContainerHigh, m3primary)
    // @param intensity: Brightness from 0 (deep black) to 1 (slightly lighter)
    // @returns: { background: color, border: color }
    function mattePill(baseColor: color, intensity: real): var {
        const clampedIntensity = Math.max(0, Math.min(1, intensity));
        const lightness = matteConstants.baseLightness + clampedIntensity * matteConstants.lightnessRange;
        const tint = matteConstants.colorTint;
        // Note: achromatic base colors (saturation ≈ 0) produce pure grey — tint only visible with chromatic bases

        const background = Qt.hsla(
            baseColor.hslHue,
            baseColor.hslSaturation * tint,
            lightness,
            1.0
        );
        const border = Qt.alpha(matteConstants.borderColor, matteConstants.borderOpacity);

        return { background: background, border: border };
    }

    // Unified pill style accessor — delegates to glassmorphism or mattePill
    // based on config toggle. Same signature and return type as glassmorphism().
    function pillStyle(baseColor: color, intensity: real): var {
        if (Appearance.pillStyle === "matte")
            return mattePill(baseColor, intensity);
        // Default / "glass": use glassmorphism as fallback for any non-"matte" value
        return glassmorphism(baseColor, intensity);
    }

    // Glassmorphism intensity presets for common use cases
    //
    // Usage Guidelines - Base Color Selection:
    //
    // BACKGROUND elements (subtle/medium):
    //   Use: Colours.palette.m3surfaceContainerHigh
    //   Examples: Workspace pills, grouped window containers, panels
    //
    // SEMANTIC elements (strong/veryStrong):
    //   Use: Colours.palette.m3primary (or m3secondary, m3tertiary, etc.)
    //   Examples: Active workspace indicator, focused window, notification badges
    //
    readonly property QtObject glass: QtObject {
        // Subtle: background elements, grouped pills
        // Layer depth: 2.4
        readonly property real subtle: 0.3

        // Medium: standard UI elements
        // Layer depth: 2.0
        readonly property real medium: 0.5

        // Strong: active/focused elements, indicators
        // Layer depth: 1.6
        readonly property real strong: 0.7

        // Very strong: prominent interactive elements
        // Layer depth: 1.2
        readonly property real veryStrong: 0.9
    }

    function load(data: string): void {
        const scheme = JSON.parse(data);

        const keys = [];
        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (current.hasOwnProperty(propName)) {
                current[propName] = `#${colour}`;
                keys.push(propName);
            }
        }
        root._paletteKeys = keys;
    }

    // Read scheme from state directory (where the CLI writes).
    // On first launch, _initScheme copies the bundled default here.
    FileView {
        id: _schemeView

        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text())
        // Silently ignore missing file on first launch — _initScheme creates it and calls reload()
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("[Colours] Failed to load scheme:", err);
        }
    }

    // Ensure state scheme file exists — copies bundled default on first launch.
    // Subsequent launches find the file already present and exit 1 (no-op).
    // onExited only calls reload() when exit code is 0 (file was actually created)
    // to avoid a redundant double-load of 111 palette keys on every startup.
    // Paths are passed as positional args ($1/$2) to avoid single-quote injection
    // from XDG_STATE_HOME or other env-derived paths.
    Process {
        id: _initScheme

        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\" && [ ! -f \"$1/scheme.json\" ] && cp \"$2\" \"$1/scheme.json\"",
            "--", Paths.state, root._defaultSchemePath
        ]
        onExited: (code, status) => {
            // code 0: file was created → reload so FileView picks it up
            // code 1: file already exists, no-op → skip reload (FileView already loaded it)
            if (code === 0)
                _schemeView.reload();
        }
    }

    IpcHandler {
        target: "theme"

        function getTheme(): string {
            const p = {};
            for (const key of root._paletteKeys)
                p[key] = String(root.palette[key]);

            return JSON.stringify({
                palette: p,
                appearance: {
                    rounding: {
                        small: Appearance.rounding.small,
                        normal: Appearance.rounding.normal,
                        large: Appearance.rounding.large,
                        full: Appearance.rounding.full,
                    },
                    spacing: {
                        small: Appearance.spacing.small,
                        smaller: Appearance.spacing.smaller,
                        normal: Appearance.spacing.normal,
                        larger: Appearance.spacing.larger,
                        large: Appearance.spacing.large,
                    },
                    padding: {
                        small: Appearance.padding.small,
                        smaller: Appearance.padding.smaller,
                        normal: Appearance.padding.normal,
                        larger: Appearance.padding.larger,
                        large: Appearance.padding.large,
                    },
                    font: {
                        family: {
                            sans: Appearance.font.family.sans,
                            mono: Appearance.font.family.mono,
                            material: Appearance.font.family.material,
                        },
                        size: {
                            small: Appearance.font.size.small,
                            smaller: Appearance.font.size.smaller,
                            normal: Appearance.font.size.normal,
                            larger: Appearance.font.size.larger,
                            large: Appearance.font.size.large,
                            extraLarge: Appearance.font.size.extraLarge,
                        },
                    },
                    anim: {
                        duration: Appearance.anim.durations.normal,
                        curves: {
                            standard: Appearance.anim.curves.standard,
                            standardDecel: Appearance.anim.curves.standardDecel,
                        },
                    },
                    transparency: {
                        enabled: Appearance.transparency.enabled,
                        base: Appearance.transparency.base,
                        layers: Appearance.transparency.layers,
                    },
                },
            });
        }
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    component Transparency: QtObject {
        readonly property bool enabled: Appearance.transparency.enabled
        readonly property real base: Appearance.transparency.base
        readonly property real layers: Appearance.transparency.layers
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3confirm: root.layer(root.palette.m3confirm)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3confirm: "#A3CCA7"
        property color m3powerButton: "#E0685F"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
