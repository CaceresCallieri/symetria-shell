# Beams background (metallic lock screen)

`assets/shaders/beams.frag` + `components/effects/BeamsBackground.qml`, tuned via
`Config.lock.beams` (schema in `config/LockConfig.qml`).

A 2D port of [React Bits `<Beams />`](https://reactbits.dev/backgrounds/beams).
Used as the lock screen background, where it also plays the reveal animation that
covers the desktop.

## Second consumer: the focus-mode backdrop

`modules/background/MetalWallpaper.qml` reuses the same shader and component as a
FROZEN backdrop shown while focus mode is active (`Config.background.focusBackdrop`).
It sits UNDER the image wallpaper stack in the background window and fades in only
when focus mode fades the images out — normal wallpapers are untouched. What is
different there:

- `animating: false` — the GPU renders one frame and idles. `time` in the config
  section selects the frozen moment; it is the composition seed.
- One beam wide enough to cover the screen (`beamWidth: 40`), so the bands read
  as a single draped sheet. **The diagonal seam across the frame is the band
  boundary at q.x = 0 and is deliberate** — the picked composition includes it.
  Any beamWidth that covers the screen puts a boundary on screen; the parameters
  cannot avoid it, only choose where it sits.
- Material knobs come from `Config.lock.beams.material` — the canonical cfg
  map — so lock and wallpaper stay one metal family; the wallpaper overrides
  only `beamWidth`, `noiseScale`, and `frontGlow` (0 — no reveal plays, the
  frame is fully opaque). Because the material is shared, lock-screen material
  tuning in shell.json changes the wallpaper too. That is intended; split the
  override object if it ever stops being wanted.

**The lock screen deliberately shows nothing but the beams and a password
field.** The upstream six-panel grid — clock, date, avatar, weather, fetch,
media, resources, notifications — was removed because the panels competed with
the background for attention; the wipe is the point of the screen. Re-adding
informational panels reverses an explicit design decision rather than filling a
gap. The eight deleted files are recoverable from history if that decision is
ever revisited.

## Why it does not need three.js

The original stacks N vertical planes, displaces their vertices in Z with 3D
Perlin noise in a vertex shader, computes analytic normals, and lights the result
with `MeshStandardMaterial` (black base, `metalness 0.3`) under **one**
directional light.

Because the base colour is pure black and metalness is low, **the diffuse term is
exactly zero**. Nothing is visible except the specular lobe of that single light.
`envMapIntensity: 10` is a no-op — there is no environment to reflect. So the
entire look reduces to: rotate UV → split into bands → evaluate a 1D height field
per band → analytic normal → GGX → tonemap. All of that is per-fragment 2D
arithmetic, which is why it ports to one `ShaderEffect` with no geometry.

Measured on the AMD Radeon 860M iGPU: 60fps sustained at 2560×1600, and still
60fps with four stacked instances (~4× the fragment work), so there is at least
4× headroom.

## Calibrations that are not obvious

**Reproducing three's F0 literally renders a black screen.** `mix(0.04, black,
0.3) = 0.028` gives a signal of ~0.03, which the grain term (subtracts up to
0.117) erases completely. three's BRDF also carries a Smith visibility term and a
π factor that together add roughly two orders of magnitude. Rather than reproduce
the full BRDF, `uLightIntensity` is a **direct gain on D**: the GGX *tail* paints
the broad bands and the peak is allowed to blow past 1.0 into the tonemap.

**The vignette is structural, not decorative.** Without it every band is lit edge
to edge and the frame reads as striped wallpaper rather than a lit scene. The
original gets this free from its perspective camera plus fog.

**Two specular lobes, not one.** A single GGX lobe reads as plastic. Real metal
has a tight highlight sitting on a wide sheen, so `uSheenRoughness` /
`uSheenStrength` add a second, much broader lobe. This is what gives the bands
breadth instead of making them a gradient.

**The microstructure must stay static.** Established empirically before this port
(machine-local, outside this repo: `~/projects/chamba-hq/website/docs/beams-metal-eval.md`
— if absent, treat the finding below as settled rather than re-litigating it): animated surface noise
reads as fake, because real metal has fixed microstructure and only its
*reflections* move. Here the noise-driven height field moves — that is the
reflection — while the per-pixel grain is derived from `gl_FragCoord` and so is
pinned to the screen. Do not "improve" this by scrolling the grain.

**Per-fragment analytic normals are safe here.** The earlier evaluation found
that `dFdx`-based bump on a mirror produces salt-and-pepper sparkle. That does not
apply: the normal here comes from a finite difference on a *smooth* analytic
field, which is the same thing the original computes per vertex.

## The reveal

`uReveal` 0 → 1 wipes the beams in. The item paints with **premultiplied alpha**:
revealed area is opaque, unrevealed area is fully transparent, so it composites
over whatever is behind it (on the lock screen, the desktop screencopy — which is
deliberately NOT blurred; see the comment at `modules/lock/LockSurface.qml`).

The front is defined in the **rotated** beam frame, so it belongs to the beams
rather than being a rectangle sliding over them:

- `across` — which beam (0 = leftmost, 1 = rightmost), delayed by `uStagger`
- `growth` — how far along a beam (0 = bottom-left end), spanned by `uGrowSpan`

**`uBeamQuantise` is the knob that produces the two staged looks.** At 0 the delay
varies continuously, so the front is a straight line sweeping the screen and the
beams have no individual identity — one diagonal wipe. At 1 every fragment of a
beam shares the delay of that beam's centre, so beams arrive one after another as
discrete objects, each still filling along its own length. Intermediate values
blend. Both looks are the same code path; there is no separate implementation.

### The normalisation that makes the timing usable

`across` and `growth` are normalised over the **rotated bounding box** of the
screen, whose corners fall *outside* the visible rectangle. Left uncorrected, a
large slice of the timeline is spent covering area nobody can see, and the wipe
appears to stall and then rush — this was visible as "nothing has happened yet at
`uReveal = 0.15`".

The fix is analytic. The reveal coordinate `u = uStagger·across + uGrowSpan·growth`
is linear in the rotated coordinates, hence linear in screen position, so writing
it as `p.x·A + p.y·B` lets its extent over the screen rectangle be solved in
closed form (`halfRange = |A|·hx + |B|·hy`). Normalising against that range spends
100% of the timeline on visible pixels.

A consequence worth knowing: **`uStagger` and `uGrowSpan` now set only the
direction of the front (their ratio), never the duration.** Duration is always
exactly one sweep of `uReveal`. Use `Config.lock.beams.revealDuration` for timing.

**The `clamp(un, 0, 1)` after that normalisation is load-bearing, not tidying.**
`halfRange` is solved from the *continuous* form of `u`, but with
`uBeamQuantise > 0` the delay snaps to each beam's centre, which can sit up to
half a beam-width outside the sampled range. Measured at the shipped defaults
(16:10, quantise 1.0), `un` reached 1.025 — leaving the corner beam at
`mask ≈ 0.82` when `uReveal` was 1, i.e. **18% of the desktop stayed visible for
the entire lock session.** Verified by rendering reveal=1 over magenta and
measuring the bleed: 47/255 before the clamp, 0/255 after. Any future change to
how `delay` is derived must preserve that clamp or re-derive `halfRange` from the
quantised form.

## Iterating on the look

Values live in `~/.config/symmetria/shell.json` under `lock.beams` (symlinked to
the tracked `config/shell.json`), which reloads live — so a lock/unlock cycle is
enough to see a change. No shell restart, no shader recompile.

Changing the shader itself does require a recompile:

```bash
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
  -o assets/shaders/beams.frag.qsb assets/shaders/beams.frag
```

### Rendering it headless

The shader can be iterated without touching the running shell. Three environment
variables are required, not two:

```bash
QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=opengl QT_QUICK_BACKEND=rhi \
  QT_LOGGING_RULES='qml=true' QT_FORCE_STDERR_LOGGING=1 qml6 harness.qml
```

`harness.qml` is written ad hoc — there is no tracked copy. The minimum is a
`Window { id: win; visible: true }` holding the `ShaderEffect` with its uniforms
set as literals, plus a `Timer` that calls `win.contentItem.grabToImage(...)` and
`Qt.quit()`. Keep it in the scratch directory, not the repo.

Without `QT_QUICK_BACKEND=rhi`, the offscreen platform falls back to the
**software** renderer, which draws `ShaderEffect` as **nothing** — no error, no
warning, and `status == Compiled`. It is easy to lose an hour chasing maths that
was already correct. Qt logging is off by default on this system, hence the last
two variables. Use `qml6`, not `qml` (the unversioned binary rejects the
unversioned imports these harnesses use).

## Gotcha: uniform names are a contract

`ShaderEffect` maps QML properties to uniforms **by name**. Renaming a property in
`BeamsBackground.qml` without renaming it in the `buf` block silently drops it —
the uniform keeps its zero-initialised value rather than raising an error.

This applies to every `ShaderEffect` in the repo, not just this one, so the full
writeup — along with the "missing/stale `.qsb` renders nothing" and headless
rendering traps — lives in `docs/qml-pitfalls.md`.
