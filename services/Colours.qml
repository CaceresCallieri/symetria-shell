pragma Singleton
pragma ComponentBehavior: Bound

import qs.config
import qs.services
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

    // Metal constants — machined dark surface.
    //
    // For SURFACES the hue is FIXED rather than derived from the palette. Metal
    // reads as metal by being chromatically neutral (a faint cool cast, as if
    // lit by daylight); tinting a surface toward whatever the palette's hue
    // happens to be turns it into coloured plastic.
    //
    // STATE colours are the deliberate exception: a caller passing a chromatic
    // baseColor (error, urgency, checked, focused) is encoding meaning, not
    // choosing a surface, so metalPill borrows that hue — capped and lifted so
    // it reads as tinted metal. See the accent constants below.
    readonly property QtObject metalConstants: QtObject {
        // Darker than matte's 0.10 — metal needs headroom above the body for the
        // specular rim to read as bright. Contrast against the highlights is
        // what sells the material, so the body is pushed down rather than the
        // highlights merely pushed up: a bright rim on a mid-grey body reads as
        // lit plastic, the same rim on a near-black body reads as metal.
        readonly property real baseLightness: 0.042
        readonly property real lightnessRange: 0.055

        // Cool cast, barely saturated. ~209° at 5%. Used for SURFACE colours —
        // see the accent constants below for the state-coded path.
        readonly property real hue: 0.58
        readonly property real saturation: 0.05

        // --- Accent path -----------------------------------------------------
        // Above this saturation, a baseColor is treated as a deliberate STATE
        // colour (error, urgency, checked, focused) rather than a surface
        // container, and metalPill borrows its hue instead of forcing neutral.
        //
        // Without this, every accent collapses to the same near-black: toast
        // types, notification urgency, filled-vs-secondary buttons, checked
        // switches and focused agent chips all become indistinguishable, since
        // the only surviving variable is `intensity` across a 0.042–0.097
        // lightness span. Several call sites even wrap the result in
        // Qt.lighter(…, 1.5), which cannot recover a hue that was discarded.
        //
        // The threshold sits above this palette's neutral containers (~0.02)
        // and below its accents, so surfaces stay machined and states stay
        // legible. Saturation is capped and lightness lifted so an accent still
        // reads as tinted metal rather than as coloured plastic.
        readonly property real accentSaturationThreshold: 0.05
        readonly property real accentSaturationMax: 0.30
        readonly property real accentLift: 0.10

        // The edge is derived from the BODY colour, lifted slightly in lightness
        // and fully opaque — it is not white at low alpha.
        //
        // This distinction is the whole point. White-at-low-alpha over a cool
        // near-black desaturates it toward neutral grey, so the outline reads as
        // a *drawn line on top of* the surface — a diagram convention. Lifting
        // the body's own colour keeps the cool cast intact, so the same pixel
        // width reads as the surface's own machined edge catching a little more
        // light than its face. Same thickness, completely different impression.
        //
        // The lift is applied to the pill's FINAL lightness (after intensity),
        // so plates at different intensities keep a consistent edge relationship
        // rather than the brighter ones losing their edge.
        readonly property real borderLightnessLift: 0.038
    }

    // Metal pill helper: near-black cool body + slightly brighter edge.
    // Same signature and return type as glassmorphism() / mattePill().
    //
    // baseColor is accepted for API symmetry but intentionally unused — see the
    // fixed-hue rationale on metalConstants.
    function metalPill(baseColor: color, intensity: real): var {
        const clampedIntensity = Math.max(0, Math.min(1, intensity));

        // A chromatic baseColor is a deliberate STATE colour, not a surface
        // container — keep its hue so the state stays readable. Desaturated
        // bases (the m3surface* family) take the neutral machined cast.
        const accented = baseColor.hslSaturation > metalConstants.accentSaturationThreshold;

        const hue = accented ? baseColor.hslHue : metalConstants.hue;
        const saturation = accented ? Math.min(metalConstants.accentSaturationMax, baseColor.hslSaturation) : metalConstants.saturation;
        const lightness = Math.min(1.0, metalConstants.baseLightness + clampedIntensity * metalConstants.lightnessRange + (accented ? metalConstants.accentLift : 0));

        const background = Qt.hsla(hue, saturation, lightness, 1.0);
        const border = Qt.hsla(hue, saturation, Math.min(1.0, lightness + metalConstants.borderLightnessLift), 1.0);

        return { background: background, border: border };
    }

    // Unified pill style accessor — delegates to the active theme's colour
    // recipe. Same signature and return type across all of them.
    //
    // Reading Theme.material HERE is what makes theme switching live: QML
    // captures binding dependencies dynamically, including properties read
    // inside a called function, so every `Colours.pillStyle(...)` binding in the
    // shell re-evaluates the moment Theme.material changes. No reload, no signal.
    function pillStyle(baseColor: color, intensity: real): var {
        if (Theme.material === "metal")
            return metalPill(baseColor, intensity);
        // Unreachable today: "glass" is not in Theme.materials, so isValidMaterial()
        // rejects it and Theme.material can never hold it. Kept — with
        // glassmorphism() — because glass is a named planned material in the
        // Theme header; wiring it up means adding a recipe block and one array
        // entry, not rewriting this dispatch. Do not delete either as dead code.
        if (Theme.material === "glass")
            return glassmorphism(baseColor, intensity);
        // Default "clay" — and any unrecognised value, matching Theme's own
        // fallback so colours and structure never disagree about the theme.
        return mattePill(baseColor, intensity);
    }

    // How far above its material's ceiling an ENGAGED part is pushed.
    //
    // Every surface recipe caps hard — metal accents top out at lightness 0.197,
    // clay at 0.18 — because a SURFACE that drifts bright stops reading as the
    // material and starts reading as coloured plastic. That cap is correct for
    // the hundreds of pills that merely carry state.
    //
    // It is wrong for the one or two controls the eye actually lands on. This
    // lift is the exception, and it is physically honest rather than a fudge:
    // an engaged part is POLISHED, not emitting. A machined face that has been
    // worn bright by use returns far more of the light source than the matte
    // stock around it, and that is a real thing metal does — unlike glowing,
    // which is what a raw `m3primary` fill was faking.
    //
    // TWO presets, because the same body lightness does not read the same in
    // every context. THE MEASUREMENT THAT PRODUCED THEM: with both parts on the
    // same 0.22 lift, the switch knob landed at 0.417 and the connected socket
    // at 0.400 — the knob objectively brighter — and the knob still looked
    // dimmer in situ. Simultaneous contrast is the reason: the knob is a small
    // disc ringed by a shadowed groove, the socket sits flat on the card. The
    // correction belongs in the value rather than in the viewer's eye, so the
    // knob was moved to its own preset and now resolves to 0.537.
    //
    // Do not "simplify" these back into one constant on the grounds that the
    // numbers should match. They differ precisely so the RESULT matches.
    readonly property QtObject polish: QtObject {
        // A part sitting in the panel plane: the connected socket.
        readonly property real standard: 0.22

        // A part ringed by a dark inset groove: the switch knob. Picked against
        // `standard` in a side-by-side render so the knob reads brighter than
        // the socket, not merely equal to it. Past a LIFT of ~0.40 (not a
        // resulting lightness of 0.40, which this preset already exceeds) it
        // stops reading as metal and starts recreating the pale disc this whole
        // rework replaced.
        readonly property real inGroove: 0.34

        // A BROAD part: the active-workspace indicator, which can be 300px+ of
        // continuous surface. The other two presets are for small controls, and
        // AREA is the variable they do not account for — the same lightness that
        // reads as a tidy highlight on a 30px disc reads as a slab that dominates
        // the whole bar when it is ten times as wide, and it stops being an
        // accent and becomes the thing you look at first.
        //
        // Numbers, kept separate because they measure different things and
        // conflating them produced a wrong rationale the first time:
        //
        //   computed body   0.1805 + lift        (this file's arithmetic)
        //   rendered        body + ~0.015, and MUCH higher inside the specular
        //                   sweep band, which on a 300px plate is wide enough
        //                   to sample by accident
        //   bar plate       0.090                (measured)
        //
        // At `standard` that is a 0.400 body rendering ~0.42, peaking past 0.50
        // across the sweep — against a 0.09 plate, with a light workspace label
        // sitting on top of it that lost most of its contrast. This preset puts
        // the body at 0.300, rendering ~0.315: not a precise midpoint, but the
        // value that stopped the plate competing with its own label when the
        // candidates were rendered side by side.
        //
        // This is why the presets are a family rather than one number: three
        // parts, all genuinely "engaged", none of which reads correctly at
        // another's value.
        readonly property real broad: 0.12
    }

    // The engaged accent every non-parameterised consumer wants: polished
    // primary at socket strength. Exists because the full call was written out
    // verbatim at three sites, which is the same drift this change set out to
    // remove — a tuning pass would have changed one and missed two.
    // ActiveIndicator deliberately keeps its own call, since its base colour is
    // supplied by the consumer (special workspaces pass tertiary).
    // intentional var: heterogeneous JS { background, border }
    readonly property var engagedAccent: engagedPillStyle(palette.m3primary, glass.strong, polish.standard)

    // pillStyle() for a part that is actuated / connected / on.
    //
    // Use this ONLY for the engaged state of an interactive control, never for
    // a container or a static display pill. It deliberately breaks the material
    // ceiling, so applying it broadly would flatten the contrast it exists to
    // create.
    //
    // `lift` is required rather than defaulted: a caller has to state which
    // context its part lives in, because picking the wrong one is invisible in
    // code review and only shows up as a control that looks flat on screen.
    // Pass a `Colours.polish.*` preset, not a literal.
    function engagedPillStyle(baseColor: color, intensity: real, lift: real): var {
        const style = pillStyle(baseColor, intensity);
        const body = style.background;
        const lit = Math.min(1.0, body.hslLightness + lift);

        // The border must keep the SAME relationship to the body that its
        // material defines, not merely inherit the unlifted edge — an edge
        // derived from the old body against a lifted one makes the plate read
        // as a flat swatch, which is the failure this function exists to avoid.
        //
        // Branch on the EDGE ITSELF, not on Theme.material. An opaque edge (as
        // metal builds by lifting the body's lightness) has to be re-derived
        // against the new body; a translucent one (clay's white-at-0.12)
        // composites correctly over any body and passes through. Testing the
        // property rather than the material name is what keeps this from
        // becoming a second per-material dispatch site parallel to pillStyle():
        // a future material gets correct behaviour by construction instead of
        // silently falling into an else branch nobody remembered to update.
        const opaqueEdge = style.border.a >= 1;

        return {
            background: Qt.hsla(body.hslHue, body.hslSaturation, lit, 1.0),
            border: opaqueEdge ? Qt.hsla(body.hslHue, body.hslSaturation, Math.min(1.0, lit + metalConstants.borderLightnessLift), 1.0) : style.border
        };
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
