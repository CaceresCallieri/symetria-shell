pragma Singleton
pragma ComponentBehavior: Bound

import qs.config
import Quickshell

// Design-language selector — TWO ORTHOGONAL AXES.
//
//   material : how an individual surface LOOKS   (clay | metal | …)
//   form     : how surfaces are ARRANGED         (islands | panel)
//
// They are separate because they have different scopes and touch different
// files. `material` is per-surface and is consumed by the three surface
// primitives. `form` is per-layout and is consumed by the bar/drawers geometry.
// Keeping them apart means "metal islands" and "clay panel" cost nothing extra;
// collapsing them into one list of themes would force a combinatorial explosion
// of near-duplicate recipes.
//
// The evidence for the split came from the metal spike: after three rounds of
// tuning the material, every remaining complaint ("it doesn't sit right at the
// top", "too many borders", "it should come from off-screen") was about form,
// and none of them could be fixed by touching a material recipe.
//
// NOTE: not every combination is designed. Ship named PRESETS that pair the two
// (e.g. "Metal Panel") rather than expecting arbitrary pairs to look good — a
// preset is a named pair, not a third axis.
//
// Symmetria's visual identity lives in a handful of SURFACE PRIMITIVES
// (PillSurface, PillToggleSurface, PillCard). Each primitive owns the
// STRUCTURE of a surface — outer shadows, body fill, rim gradients, content
// clipping — while this singleton owns the NUMBERS that give that structure a
// material character.
//
// Adding a new material (glass, paper, …) therefore means adding a data block
// here, NOT writing a parallel implementation of every primitive. Every recipe
// must expose the SAME property names so primitives can bind to them without
// knowing which theme is active. A theme that omits a key inherits nothing —
// it renders `undefined` — so blocks are written out in full, deliberately,
// even where a value repeats.
//
// `material` and `form` are plain writable properties, NOT readonly: the IPC handler in
// modules/Shortcuts.qml assigns to them. Marking them readonly would make those
// assignments silently no-op — see the `readonly property blocks ALL assignment`
// pitfall in docs/qml-pitfalls.md.
//
// Switching is live and needs no reload: QML captures binding dependencies
// dynamically, so every `Theme.pill.*` binding across the shell re-evaluates
// the moment either changes.
//
// NOT PERSISTED YET. Both axes reset to the defaults above on every shell start;
// switch at runtime with `symmetria shell surface material clay` /
// `symmetria shell surface form islands`. Changing the shipped default means
// editing the initialisers below — that is the intended knob until persistence
// lands. Persistence was deliberately deferred:
// the obvious home is ~/.config/symmetria/shell.json, but JSON overrides WIN
// over QML defaults, so a theme that wants to change a value the user has
// pinned there (transparency is the live example — metal wants it off, the
// user has it on at base 0.3) cannot. Resolving that ownership question is a
// prerequisite for persisting, not an afterthought.
Singleton {
    id: root

    // intentional var: plain JS arrays, NOT `list<string>`. The JS array API
    // (includes/indexOf/join) is what the IPC handler needs, and QML's
    // `list<string>` does not reliably expose it.
    readonly property var materials: ["clay", "metal"]
    readonly property var forms: ["islands", "panel"]

    // Shipped default: rounded metal — metal plates in the islands form.
    property string material: "metal"
    property string form: "islands"

    // Theme owns its own semantics so callers (IPC, future UI) never have to
    // reimplement validation or ordering.
    function isValidMaterial(name: string): bool {
        return materials.includes(name);
    }

    function isValidForm(name: string): bool {
        return forms.includes(name);
    }

    /// Advances to the next entry in `list`, wrapping around.
    function _next(list: var, value: string): string {
        return list[(list.indexOf(value) + 1) % list.length];
    }

    function cycleMaterial(): void {
        material = _next(materials, material);
    }

    function cycleForm(): void {
        form = _next(forms, form);
    }

    // --- Recipe vocabulary ---------------------------------------------------
    //
    // Shadow/rim keys map onto the primitives' existing property names.
    // The `finish` keys below drive components/effects/SurfaceFinish.qml and are
    // all zero for clay, which makes that overlay render nothing — the clay look
    // is bit-for-bit what it was before the theme system existed.
    //
    //   sheenTop        top-of-body lightening (vertical gradient)
    //   sweepAlpha      horizontal specular band — the light source's reflection
    //   sweepCentre     where that band sits across the width (0..1, off-centre)
    //   sweepWidth      how broad it is (fraction of width)
    //   brushedAlpha    static anisotropic micro-texture (brushed metal)
    //   rimAlpha        specular edge line along the very top
    //   rimStop         how fast that rim falls off (fraction of height)
    //   rimBottomAlpha  dimmer edge line along the bottom (bevel fill light)
    //   rimBottomStop   how fast the bottom rim falls off
    //
    // Why the micro-texture is STATIC: animated surface noise reads as fake —
    // real metal microstructure is fixed and only the REFLECTIONS move. This was
    // established empirically; do not "improve" it by scrolling the texture.

    // intentional var: heterogeneous JS data table, indexed by theme name
    readonly property var _recipes: ({
        clay: {
            pill: {
                darkShadowOffsetX: 2, darkShadowOffsetY: 3, darkShadowBlur: 12, darkShadowAlpha: 0.40,
                lightShadowOffsetX: -2, lightShadowOffsetY: -2, lightShadowBlur: 8, lightShadowAlpha: 0.10,
                highlightAlpha: 0.08, innerShadowAlpha: 0.0, borderWidth: 1,
                sheenTop: 0.0, sweepAlpha: 0.0, sweepCentre: 0.5, sweepWidth: 0.3,
                brushedAlpha: 0.0, rimAlpha: 0.0, rimStop: 0.05, rimBottomAlpha: 0.0, rimBottomStop: 0.05
            },
            toggle: {
                darkShadowOffsetX: 2, darkShadowOffsetY: 4, darkShadowBlur: 10, darkShadowAlpha: 0.55,
                lightShadowOffsetX: -2, lightShadowOffsetY: -2, lightShadowBlur: 8, lightShadowAlpha: 0.12,
                highlightAlpha: 0.04, innerShadowAlpha: 0.0, borderWidth: 0,
                darkInsetAlpha: 0.55, lightInsetAlpha: 0.12, horizontalInsetWeight: 0.50,
                sheenTop: 0.0, sweepAlpha: 0.0, sweepCentre: 0.5, sweepWidth: 0.3,
                brushedAlpha: 0.0, rimAlpha: 0.0, rimStop: 0.05, rimBottomAlpha: 0.0, rimBottomStop: 0.05
            },
            card: {
                darkShadowOffsetX: 3, darkShadowOffsetY: 4, darkShadowBlur: 14, darkShadowAlpha: 0.28,
                lightShadowOffsetX: -3, lightShadowOffsetY: -3, lightShadowBlur: 11, lightShadowAlpha: 0.07,
                highlightAlpha: 0.08, innerShadowAlpha: 0.03, borderWidth: 1,
                sheenTop: 0.0, sweepAlpha: 0.0, sweepCentre: 0.5, sweepWidth: 0.3,
                brushedAlpha: 0.0, rimAlpha: 0.0, rimStop: 0.03, rimBottomAlpha: 0.0, rimBottomStop: 0.03
            }
        },

        // Metal: a FLAT machined plate.
        //
        // The defining difference from clay is not colour or texture — it is
        // FORM. Clay (and glass) describe a rounded, extruded object: two
        // opposing outer shadows lift it off the backdrop, a broad top rim and a
        // vertical sheen imply a curved top face, a bottom inner shadow seats it
        // in a well. Every one of those cues says "this bulges toward you".
        //
        // Metal is a plate cut from stock. It has no bulge, so it gets NO outer
        // shadows, NO sheen, NO inner shadow, and no bottom bevel rim. What is
        // left is what a flat plate actually shows: a broad soft reflection of
        // the light source travelling across the face, and the machining grain.
        //
        // borderWidth is 1, but the colour is NOT a white outline — metalPill()
        // derives it from the body colour lifted slightly in lightness, so it
        // reads as the plate's own machined edge rather than a line drawn on
        // top of it. See metalConstants.borderLightnessLift in
        // services/Colours.qml for why that distinction matters more than the
        // thickness does.
        //
        // The light band still carries most of the silhouette — `sweepAlpha` was
        // raised when the white outline came off and stays raised; the edge
        // defines where the plate ENDS, the sweep is what makes it read as lit.
        //
        // `rimAlpha` still applies to cards, but is effectively invisible on BAR
        // plates under the panel form — the rim lives in the top few percent of
        // the plate, and those pixels are the ones bleeding off-screen.
        //
        // The toggle keeps its INSET gradient, because that encodes STATE (is
        // this on?) rather than decoration — but it drops the light/horizontal
        // components, so a pressed metal toggle darkens flatly instead of
        // dishing into a neumorphic well.
        metal: {
            pill: {
                darkShadowOffsetX: 0, darkShadowOffsetY: 0, darkShadowBlur: 0, darkShadowAlpha: 0.0,
                lightShadowOffsetX: 0, lightShadowOffsetY: 0, lightShadowBlur: 0, lightShadowAlpha: 0.0,
                highlightAlpha: 0.0, innerShadowAlpha: 0.0, borderWidth: 1,
                sheenTop: 0.0, sweepAlpha: 0.070, sweepCentre: 0.30, sweepWidth: 0.46,
                brushedAlpha: 0.040, rimAlpha: 0.20, rimStop: 0.020, rimBottomAlpha: 0.0, rimBottomStop: 0.03
            },
            toggle: {
                darkShadowOffsetX: 0, darkShadowOffsetY: 0, darkShadowBlur: 0, darkShadowAlpha: 0.0,
                lightShadowOffsetX: 0, lightShadowOffsetY: 0, lightShadowBlur: 0, lightShadowAlpha: 0.0,
                highlightAlpha: 0.0, innerShadowAlpha: 0.0, borderWidth: 1,
                darkInsetAlpha: 0.42, lightInsetAlpha: 0.0, horizontalInsetWeight: 0.0,
                sheenTop: 0.0, sweepAlpha: 0.070, sweepCentre: 0.30, sweepWidth: 0.46,
                brushedAlpha: 0.040, rimAlpha: 0.20, rimStop: 0.020, rimBottomAlpha: 0.0, rimBottomStop: 0.03
            },
            card: {
                darkShadowOffsetX: 0, darkShadowOffsetY: 0, darkShadowBlur: 0, darkShadowAlpha: 0.0,
                lightShadowOffsetX: 0, lightShadowOffsetY: 0, lightShadowBlur: 0, lightShadowAlpha: 0.0,
                highlightAlpha: 0.0, innerShadowAlpha: 0.0, borderWidth: 1,
                sheenTop: 0.0, sweepAlpha: 0.055, sweepCentre: 0.26, sweepWidth: 0.52,
                brushedAlpha: 0.032, rimAlpha: 0.15, rimStop: 0.008, rimBottomAlpha: 0.0, rimBottomStop: 0.01
            }
        }
    })

    // Falls back to clay for any unknown name so a bad IPC argument degrades to
    // the default look instead of rendering undefined everywhere.
    // intentional var: JS recipe object from the table above
    readonly property var recipe: _recipes[material] ?? _recipes.clay

    // intentional var: per-role JS recipe blocks consumed by the surface primitives
    readonly property var pill: recipe.pill
    readonly property var toggle: recipe.toggle
    readonly property var card: recipe.card

    // --- FORM axis -----------------------------------------------------------
    //
    //   barPaddingMode  "border" → the bar insets its content by
    //                              max(padding.smaller, border.thickness), the
    //                              historical rule that makes the bar float as a
    //                              detached island below the screen edge.
    //                   "flush"  → no inset at all; the bar content sits hard
    //                              against the top of the screen.
    //
    //   barTopBleed     How far each bar plate extends ABOVE the screen edge, in
    //                   px. The plate is grown by this amount and bottom-aligned,
    //                   so the excess — including its top border and specular rim
    //                   — falls outside the layer-shell surface and is clipped by
    //                   the compositor.
    //
    //                   This is the honest way to get "no top edge": rather than
    //                   drawing three borders and skipping the fourth, the panel
    //                   genuinely continues past the screen. It also means the
    //                   plate reads as a slab entering the frame from outside
    //                   rather than as a chip sitting inside it.
    //
    //                   Consumers must offset their content down by bleed/2 to
    //                   keep it centred on the VISIBLE part of the plate.
    //
    //   surfaceRounding Multiplier on the surface primitives' corner radius.
    //                   1 keeps the configured rounding, 0 squares them off.
    //
    //                   SCOPE: this is SHELL-WIDE, not bar-only. It multiplies
    //                   the radius of every PillSurface, PillToggleSurface and
    //                   PillCard — control center, notifications, dashboard,
    //                   launcher and toasts included. That is deliberate: form
    //                   is a whole-shell silhouette choice, and a shell with
    //                   square bar plates but rounded cards reads as unfinished
    //                   rather than as a style. The screen-edge argument below
    //                   motivates PAIRING rounding with bleed; it is not the
    //                   limit of rounding's reach.
    //
    // WHY ROUNDING AND BLEED LIVE IN THE SAME RECIPE: they are one decision, not
    // two. A capsule that bleeds past the screen edge gets its top arc sliced
    // off, leaving a flat-topped shape with curved sides — it reads as a
    // rendering bug rather than as a panel entering the frame. Bleeding only
    // looks deliberate on a SQUARE plate, whose silhouette is unchanged by the
    // cut. Pairing them here makes the broken combination unreachable: you
    // cannot select round-and-bleeding, because no recipe expresses it.
    //
    // intentional var: heterogeneous JS data table, indexed by form name
    readonly property var _forms: ({
        // Detached rounded chips floating below the screen edge.
        islands: {
            surfaceRounding: 1,
            barPaddingMode: "border",
            barTopBleed: 0
        },
        // Square slabs running off the top of the screen.
        panel: {
            surfaceRounding: 0,
            barPaddingMode: "flush",
            barTopBleed: 10
        }
    })

    // intentional var: JS recipe object from the table above
    readonly property var layout: _forms[form] ?? _forms.islands

    // --- Derived bar-plate geometry ------------------------------------------
    //
    // CONTRACT: every bar entry that draws its own plate (PillContainer, Tray,
    // Workspaces) MUST size itself with `barPlateHeight` and offset its content
    // by `barPlateContentOffset`. Deriving both here rather than recomputing
    // `innerWidth + bleed` and `bleed / 2` per file keeps the bleed a single
    // source of truth — the first version of this feature open-coded it in two
    // places and Workspaces was silently missed, which is exactly the drift this
    // prevents. A fourth plate producer only has to read these two properties.
    //
    // The offset is ROUNDED: an odd bleed would otherwise place content on a
    // half pixel and blur every icon and label in the bar.
    readonly property int barPlateHeight: Config.bar.sizes.innerWidth + layout.barTopBleed
    readonly property int barPlateContentOffset: Math.round(layout.barTopBleed / 2)

    // Dev guard for the "every recipe exposes the SAME keys" invariant the
    // header states. A material that omits a key renders `undefined` into a
    // primitive's binding with no error at the definition site, so prose alone
    // is not enough — this turns a silent mis-render into a startup warning.
    Component.onCompleted: {
        for (const role of ["pill", "toggle", "card"]) {
            const reference = Object.keys(_recipes.clay[role]).sort().join(",");
            for (const name of materials) {
                const keys = Object.keys(_recipes[name][role]).sort().join(",");
                if (keys !== reference)
                    console.warn(`[Theme] recipe ${name}.${role} key set differs from clay.${role}`);
            }
        }
    }
}
