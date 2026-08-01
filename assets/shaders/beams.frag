#version 440

// 2D port of React Bits <Beams /> — reproduces the look WITHOUT three.js,
// meshes, or a PBR pipeline.
//
// The original displaces stacked plane geometry with 3D Perlin noise in a
// vertex shader and lets MeshStandardMaterial's GGX specular from ONE
// directional light paint the highlight. Because the diffuse base is pure
// black and metalness is low, the diffuse term is exactly zero — literally
// nothing is visible except the specular lobe. That is what makes the whole
// effect portable: it can be computed analytically per fragment in 2D.
//
// Beyond the port, this version adds a REVEAL: a moving front that wipes the
// beams in over whatever is behind them. See the "reveal" section below — it is
// the piece the lock screen animates.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    // qt_Matrix and qt_Opacity must both be present when the built-in vertex
    // shader is used.
    mat4 qt_Matrix;
    float qt_Opacity;

    float time;
    float uSpeed;
    float uScale;
    float uNoiseIntensity;
    float uBeamWidth;
    float uRotation;
    float uRoughness;
    float uLightIntensity;
    float uAmbient;
    float uEdgeDarken;

    // Reveal
    float uReveal;
    float uStagger;
    float uGrowSpan;
    float uBeamQuantise;
    float uFeather;
    float uFrontGlow;
    float uGrowFlip;

    // Realism
    float uSheenRoughness;
    float uSheenStrength;
    float uFresnel;

    vec2 uResolution;
    vec4 uLightColour;
    vec4 uLightDir;
};

// --- noise (verbatim from React Bits Beams.jsx) -------------------------
float random(in vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}
vec4 permute(vec4 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
vec3 fade(vec3 t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }
float cnoise(vec3 P) {
    vec3 Pi0 = floor(P);
    vec3 Pi1 = Pi0 + vec3(1.0);
    Pi0 = mod(Pi0, 289.0);
    Pi1 = mod(Pi1, 289.0);
    vec3 Pf0 = fract(P);
    vec3 Pf1 = Pf0 - vec3(1.0);
    vec4 ix = vec4(Pi0.x, Pi1.x, Pi0.x, Pi1.x);
    vec4 iy = vec4(Pi0.yy, Pi1.yy);
    vec4 iz0 = Pi0.zzzz;
    vec4 iz1 = Pi1.zzzz;
    vec4 ixy = permute(permute(ix) + iy);
    vec4 ixy0 = permute(ixy + iz0);
    vec4 ixy1 = permute(ixy + iz1);
    vec4 gx0 = ixy0 / 7.0;
    vec4 gy0 = fract(floor(gx0) / 7.0) - 0.5;
    gx0 = fract(gx0);
    vec4 gz0 = vec4(0.5) - abs(gx0) - abs(gy0);
    vec4 sz0 = step(gz0, vec4(0.0));
    gx0 -= sz0 * (step(0.0, gx0) - 0.5);
    gy0 -= sz0 * (step(0.0, gy0) - 0.5);
    vec4 gx1 = ixy1 / 7.0;
    vec4 gy1 = fract(floor(gx1) / 7.0) - 0.5;
    gx1 = fract(gx1);
    vec4 gz1 = vec4(0.5) - abs(gx1) - abs(gy1);
    vec4 sz1 = step(gz1, vec4(0.0));
    gx1 -= sz1 * (step(0.0, gx1) - 0.5);
    gy1 -= sz1 * (step(0.0, gy1) - 0.5);
    vec3 g000 = vec3(gx0.x, gy0.x, gz0.x);
    vec3 g100 = vec3(gx0.y, gy0.y, gz0.y);
    vec3 g010 = vec3(gx0.z, gy0.z, gz0.z);
    vec3 g110 = vec3(gx0.w, gy0.w, gz0.w);
    vec3 g001 = vec3(gx1.x, gy1.x, gz1.x);
    vec3 g101 = vec3(gx1.y, gy1.y, gz1.y);
    vec3 g011 = vec3(gx1.z, gy1.z, gz1.z);
    vec3 g111 = vec3(gx1.w, gy1.w, gz1.w);
    vec4 norm0 = taylorInvSqrt(vec4(dot(g000, g000), dot(g010, g010), dot(g100, g100), dot(g110, g110)));
    g000 *= norm0.x; g010 *= norm0.y; g100 *= norm0.z; g110 *= norm0.w;
    vec4 norm1 = taylorInvSqrt(vec4(dot(g001, g001), dot(g011, g011), dot(g101, g101), dot(g111, g111)));
    g001 *= norm1.x; g011 *= norm1.y; g101 *= norm1.z; g111 *= norm1.w;
    float n000 = dot(g000, Pf0);
    float n100 = dot(g100, vec3(Pf1.x, Pf0.yz));
    float n010 = dot(g010, vec3(Pf0.x, Pf1.y, Pf0.z));
    float n110 = dot(g110, vec3(Pf1.xy, Pf0.z));
    float n001 = dot(g001, vec3(Pf0.xy, Pf1.z));
    float n101 = dot(g101, vec3(Pf1.x, Pf0.y, Pf1.z));
    float n011 = dot(g011, vec3(Pf0.x, Pf1.yz));
    float n111 = dot(g111, Pf1);
    vec3 fade_xyz = fade(Pf0);
    vec4 n_z = mix(vec4(n000, n100, n010, n110), vec4(n001, n101, n011, n111), fade_xyz.z);
    vec2 n_yz = mix(n_z.xy, n_z.zw, fade_xyz.y);
    float n_xyz = mix(n_yz.x, n_yz.y, fade_xyz.x);
    return 2.2 * n_xyz;
}

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453123);
}

// Height field along one beam. In the original this is
// cnoise(vec3(pos.x*0., pos.y - uv.y, time*speed*3.) * scale) — x is zeroed,
// so the wave only varies ALONG the beam, and each beam gets its own random
// uv offset so neighbours are decorrelated.
float beamHeight(float along, float seed, float t) {
    return cnoise(vec3(0.0, along - seed, t * uSpeed * 3.0) * uScale);
}

// GGX normal distribution. The blown-out core of this lobe IS the highlight.
float ggx(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * d * d);
}

void main() {
    vec2 res = uResolution;
    float aspect = res.x / max(res.y, 1.0);

    // World-space plane, ~15 units tall to match beamHeight = 15
    float hx = aspect * 7.5;
    float hy = 7.5;
    vec2 p = (qt_TexCoord0 - 0.5) * vec2(aspect, 1.0) * 15.0;

    float c = cos(uRotation);
    float s = sin(uRotation);
    vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y);

    float band = q.x / uBeamWidth;
    float bid = floor(band);
    float local = fract(band);

    float seed = hash11(bid) * 300.0;
    float along = q.y;

    // ---- reveal --------------------------------------------------------
    // The front is expressed in the ROTATED frame, so it belongs to the beams
    // rather than being a rectangle sliding over them.
    //
    //   across  : 0 at the leftmost beam, 1 at the rightmost   (which beam)
    //   growth  : 0 at a beam's bottom-left end, 1 at its top-right end
    //             (where along a beam)
    //
    // Rotating a rectangle of half-extents (hx, hy) gives these analytic
    // bounds — needed because q's range depends on uRotation.
    float qxMax = max(abs(c) * hx + abs(s) * hy, 1e-4);
    float qyMax = max(abs(s) * hx + abs(c) * hy, 1e-4);

    // +q.y points toward the BOTTOM-LEFT of the screen, so the default
    // (uGrowFlip = 0) fills each beam from its bottom-left end toward its
    // top-right end. Flipping sends the front the other way.
    float gs = mix(-1.0, 1.0, uGrowFlip);

    float across = q.x / qxMax * 0.5 + 0.5;
    float growth = 0.5 + gs * q.y / qyMax * 0.5;

    // uBeamQuantise is the knob that separates the two looks. At 0 the delay
    // varies continuously across x, so the front is a straight line sweeping
    // the screen — the beams have no individual identity and it reads as ONE
    // diagonal wipe. At 1 every fragment of a beam shares the delay of that
    // beam's centre, so beams snap in one after another as discrete objects.
    // Within a beam `growth` still varies either way, so a beam always fills
    // along its own length rather than appearing all at once.
    float bandCentreQx = (bid + 0.5) * uBeamWidth;
    float acrossQuantised = bandCentreQx / qxMax * 0.5 + 0.5;
    float delay = mix(across, acrossQuantised, uBeamQuantise);

    float u = uStagger * delay + uGrowSpan * growth;

    // Normalise `u` over the range it actually takes ON SCREEN.
    //
    // This matters more than it looks. `across`/`growth` are normalised over the
    // ROTATED bounding box, whose corners fall outside the visible rectangle —
    // so without this correction a large slice of the timeline is spent covering
    // area nobody can see, and the wipe appears to stall and then rush.
    //
    // `u` is linear in q, hence linear in p, so writing it as p.x*A + p.y*B lets
    // its extent over the screen rectangle be solved in closed form.
    float A = uStagger * c / (2.0 * qxMax) + uGrowSpan * gs * s / (2.0 * qyMax);
    float B = -uStagger * s / (2.0 * qxMax) + uGrowSpan * gs * c / (2.0 * qyMax);
    float halfRange = max(abs(A) * hx + abs(B) * hy, 1e-4);
    float uCentre = 0.5 * (uStagger + uGrowSpan);
    float un = (u - (uCentre - halfRange)) / (2.0 * halfRange);

    // A consequence worth knowing: because the range is renormalised, uStagger
    // and uGrowSpan now set only the DIRECTION of the front (their ratio), never
    // the duration. Duration is always exactly one full sweep of uReveal 0 -> 1.
    float feather = max(uFeather, 1e-4);
    float front = uReveal * (1.0 + feather) - un;
    float mask = clamp(front / feather, 0.0, 1.0);

    // ---- lighting ------------------------------------------------------
    // Analytic normal: the surface is z = h(along), so the tangent along the
    // beam is (0, 1, dh) and across it is (1, 0, 0) → N = (0, -dh, 1).
    // The original computes this per-VERTEX with the same finite difference;
    // doing it per-fragment on a SMOOTH field is safe (the aliasing trap noted
    // in the earlier evaluation came from dFdx on a mirror, not from this).
    float e = 0.03;
    float h0 = beamHeight(along, seed, time);
    float h1 = beamHeight(along + e, seed, time);
    float dh = (h1 - h0) / e;

    vec3 N = normalize(vec3(0.0, -dh, 1.0));
    vec3 V = vec3(0.0, 0.0, 1.0);
    vec3 L = normalize(uLightDir.xyz);
    vec3 H = normalize(L + V);

    float NdotH = max(dot(N, H), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    // Calibration note: reproducing three's F0 literally (mix(0.04, black, 0.3)
    // = 0.028) renders the whole frame black — the grain term subtracts up to
    // 0.117, which swamps a 0.03 signal. three's BRDF also carries a Smith
    // visibility term and a PI factor that together add roughly two orders of
    // magnitude. Rather than reproduce the full BRDF, uLightIntensity is a
    // direct gain on D: the GGX *tail* paints the broad bands and the peak is
    // allowed to blow past 1.0 into the tonemap.
    float spec = ggx(NdotH, uRoughness) * uLightIntensity * mix(0.4, 1.0, NdotL);

    // Second, much broader lobe. A single GGX lobe reads as plastic because
    // real metal has a tight highlight sitting ON a wide sheen; splitting the
    // response into two roughnesses is the cheapest way to get that, and it is
    // what makes the bands feel like they have breadth rather than being a
    // gradient. Scaled by the tight lobe's intensity so one knob still governs
    // overall brightness.
    spec += ggx(NdotH, uSheenRoughness) * uLightIntensity * uSheenStrength * mix(0.4, 1.0, NdotL);

    // Schlick Fresnel. On this surface N is mostly +z, so 1-NdotV is only large
    // on the steep flanks of the height field — exactly the beam edges. It
    // gives those edges definition without brightening the flats.
    float fresnel = pow(1.0 - NdotV, 5.0);
    spec *= 1.0 + uFresnel * fresnel;

    // Beams displaced toward the camera read marginally brighter (the original
    // gets this for free from perspective + fog).
    float depth = h0 * 0.5 + 0.5;
    float ambient = uAmbient * (0.35 + 0.65 * depth);

    // Seam between adjacent beams
    float edge = smoothstep(0.0, 0.02, local) * smoothstep(0.0, 0.02, 1.0 - local);
    float shade = mix(1.0 - uEdgeDarken, 1.0, edge);

    // Vignette — the original gets this free from the perspective camera + fog;
    // without it every band is lit edge to edge and the frame reads as wallpaper
    // stripes rather than a lit scene. Structural, not decorative.
    vec2 vc = qt_TexCoord0 - 0.5;
    float vig = 1.0 - smoothstep(0.25, 0.78, length(vc * vec2(1.0, 1.15)));

    vec3 col = (uLightColour.rgb * spec + vec3(ambient)) * shade * mix(0.15, 1.0, vig);

    // Leading edge of the reveal glows: the front is where the beam is being
    // "drawn", and without it the wipe reads as a rectangle of opacity rather
    // than as the beams arriving. Peaks in the middle of the feather band and
    // vanishes once the fragment is fully revealed or not yet reached.
    float frontBand = mask * (1.0 - mask) * 4.0;
    col += uLightColour.rgb * frontBand * uFrontGlow;

    // Reinhard-ish rolloff so the blown core stays white instead of clipping hard
    col = col / (1.0 + col * 0.35);

    // Per-pixel grain — this is the surface roughness of the reference
    float g = random(gl_FragCoord.xy);
    col -= g / 15.0 * uNoiseIntensity;

    // Premultiplied alpha: the revealed area is fully OPAQUE (alpha 1) so it
    // covers whatever sits behind — on the lock screen that is the desktop
    // screencopy. Multiplying colour by mask as well keeps it premultiplied,
    // which is what Qt Quick's blend expects.
    col = max(col, vec3(0.0)) * mask;
    fragColor = vec4(col, mask) * qt_Opacity;
}
