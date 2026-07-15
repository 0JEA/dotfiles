#version 300 es
// highp is REQUIRED, not a nicety: mediump carries ~10 mantissa bits, so at a
// noise coordinate of ~47 the ULP is ~0.046 and fract() — which the value-noise
// lattice is built on — loses nearly all its precision. Under mediump the fine
// grain literally computes into rounding error (measured 0.12% luminance
// variation, ~10x below the perceptual floor).
precision highp float;
precision highp int;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

#define TWO_PI 6.28318530718
#define STRENGTH 1.0

// ---------------------------------------------------------------------------
// PCG2D integer hash — Jarzynski & Olano, JCGT 9(3) 2020.
// sin()/fract() hashes give visible grid artifacts here, and sin() is a
// transcendental: an earlier revision blew the per-frame budget and the
// driver truncated the frame to black. PCG is pure cheap integer ALU.
// ---------------------------------------------------------------------------
uvec2 pcg2d(uvec2 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v ^= v >> 16u;
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v ^= v >> 16u;
    return v;
}
// int->uint is a defined 2's-complement reinterpret; float->uint is UNDEFINED
// for negatives, and the inter-octave rotation below does produce negatives.
float hash21(vec2 p) {
    uvec2 h = pcg2d(uvec2(ivec2(floor(p))));
    return float(h.x) / 4294967295.0;
}
vec2 hash22(vec2 p) {
    uvec2 h = pcg2d(uvec2(ivec2(floor(p))));
    return vec2(h) / 4294967295.0;
}

float valueNoise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

const mat2 ROT = mat2(0.7648, -0.6442, 0.6442, 0.7648); // rotate(0.7rad): anti-tiling

float fbm3(vec2 n);

// normalised to ~0..1. The reference's fbm starts at amplitude .4 (max .83);
// mine starts at 1.0 (max 1.96). Feeding an un-normalised fbm into the
// 8*x^3 fade curve saturates it to 1.0 everywhere, which silently switches
// folds and scratches OFF entirely — the bug that made them "invisible".
float fbm3n(vec2 n) { return fbm3(n) * (1.0 / 1.96); }

float fbm3(vec2 n) {
    float total = 0.0, amp = 1.0;
    for (int i = 0; i < 3; i++) {
        n = ROT * n;
        total += valueNoise(n) * amp;
        n *= 2.0;
        amp *= 0.6;
    }
    return total;
}

// ---------------------------------------------------------------------------
// FIBER — gradient MAGNITUDE of fbm. Ridges form along noise contours, giving
// curly filament structure (real pulp) instead of flat grain. This is the
// mid-frequency band my earlier versions were missing entirely.
// ---------------------------------------------------------------------------
float fiberNoise(vec2 uv) {
    const float e = 0.002;
    float n1 = fbm3(uv + vec2(e, 0.0));
    float n2 = fbm3(uv - vec2(e, 0.0));
    float n3 = fbm3(uv + vec2(0.0, e));
    float n4 = fbm3(uv - vec2(0.0, e));
    return length(vec2(n1 - n2, n3 - n4)) / (2.0 * e);
}

// ---------------------------------------------------------------------------
// FOLDS — nearest-of-N random centres; returns the offset vector toward the
// nearest centre, faded by distance. Sampled twice at slightly offset UVs and
// summed: where the nearest-centre assignment flips, the vectors disagree and
// a crease ridge appears. Organic radial creases, not straight lines.
// ---------------------------------------------------------------------------
vec2 folds(vec2 uv, float count, float seed) {
    vec3 pp = vec3(0.0);
    float l = 9.0;
    for (float i = 0.0; i < 8.0; i++) {
        if (i >= count) break;
        vec2 rnd = hash22(vec2(i * 7.0 + 3.0, i * 13.0 + seed * 17.0 + 5.0));
        float an = rnd.x * TWO_PI;
        vec2 p = vec2(cos(an), sin(an)) * rnd.y;
        float dist = distance(uv, p);
        if (dist < l) {
            l = dist;
            pp.xy = uv - p;
            pp.z = dist;
        }
    }
    return mix(pp.xy, vec2(0.0), sqrt(sqrt(clamp(pp.z, 0.0, 1.0)))); // pow(z,.25)
}

// CRUMPLES: removed. The ^16 cell weighting made each cell nearly flat with
// hard edges, so its derivative became a hard line network that read as
// crumpled foil, not paper. Folds already supply the low-frequency
// undulation, and on a text page the extra layer only added busy-ness.

// ---------------------------------------------------------------------------
// SCRATCHES — sparse, jittered, randomized length/width/curve/depth per cell.
// `wear` (0..1) is the curvature-driven mask: raised areas get rubbed more.
// ---------------------------------------------------------------------------
float scratches(vec2 p, float wear) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    // wear raises local scratch probability — Substance's curvature-driven wear
    float thresh = mix(0.985, 0.90, clamp(wear, 0.0, 1.0));
    float exists = step(thresh, hash21(cell * 5.0 + 31.0));
    vec2 jitter = hash22(cell * 9.0 + 61.0) * 0.5 + 0.25;
    vec2 centered = f - jitter;
    float angle = hash21(cell * 3.0 + 97.0) * TWO_PI;
    vec2 dir = vec2(cos(angle), sin(angle));
    float along = dot(centered, dir);
    float perp = centered.x * -dir.y + centered.y * dir.x;
    perp += (hash21(cell * 11.0 + 131.0) - 0.5) * 0.6 * along * along;  // curve
    float halfLen = mix(0.10, 0.34, hash21(cell * 13.0 + 167.0));
    float width  = mix(0.010, 0.024, hash21(cell * 17.0 + 197.0));
    float depth  = mix(0.20, 1.0, hash21(cell * 19.0 + 233.0));
    float mask = step(abs(along), halfLen) * (1.0 - smoothstep(0.0, width, abs(perp)));
    float endFade = 1.0 - smoothstep(halfLen * 0.7, halfLen, abs(along));
    return exists * mask * endFade * depth;
}

// --- tuning (scaled by STRENGTH) -------------------------------------------
const float U_ROUGHNESS = 0.50 * STRENGTH;
const float U_FIBER     = 0.28 * STRENGTH;
const float U_FOLDS     = 0.35 * STRENGTH;
const float U_SCRATCH   = 0.30 * STRENGTH;
const float U_AO        = 0.35 * STRENGTH;
const float U_FOLDCOUNT = 7.0;
const float U_SEED      = 3.0;
const float U_FADE      = 0.70;  // input to the 8*x^3 curve; must keep it unsaturated
const float U_RELIEF_Z  = 1.8;   // NOT strength-scaled; STRENGTH drives amplitude

void main() {
    vec4 pixColor = texture(tex, v_texcoord);

    vec2 res = vec2(textureSize(tex, 0));
    // MUST be centred on 0: fold centres are placed in a unit circle about the
    // origin, so an uncentred 0..N range puts them all off-screen and leaves a
    // single giant radial gradient instead of interacting crease cells.
    vec2 patternUV = 5.0 * (v_texcoord - 0.5) * vec2(res.x / res.y, 1.0);

    // --- FADE: big-scale mask, cubed. Real paper is not uniformly distressed.
    // Without this every effect is statistically stationary — the single
    // biggest "this is procedural" tell.
    float fade = U_FADE * fbm3n(patternUV * 0.17 + U_SEED * 3.0);
    fade = clamp(8.0 * fade * fade * fade, 0.0, 1.0);

    // --- Each feature contributes its gradient AT ITS OWN SCALE. One global
    // epsilon cannot see both pixel-scale grain and page-scale folds — that is
    // precisely why the folds were invisible in the previous version.
    vec2 normal = vec2(0.0);

    // roughness — pixel scale (±1px)
    vec2 rUv = 1.5 * (gl_FragCoord.xy - 0.5 * res);
    float rough = fbm3((rUv + vec2(1.0, 0.0)) * 0.1) - fbm3((rUv - vec2(1.0, 0.0)) * 0.1);

    // fiber — curly filaments, mid band
    float fiber = 0.5 * (fiberNoise(patternUV * 2.2) - 1.0);

    // folds — page scale, twice at offset UV; creases where assignment flips
    vec2 fUv = patternUV * 0.22;
    vec2 w  = folds(fUv, U_FOLDCOUNT, U_SEED);
    vec2 w2 = folds(fUv + 0.007, U_FOLDCOUNT, U_SEED);
    vec2 ridge = max(vec2(0.0), w + w2);

    // curvature-driven wear: scratches concentrate on raised crease ridges,
    // which also *correlates* the layers instead of stacking them independently
    float wear = clamp(length(ridge) * 2.5, 0.0, 1.0);
    float scr = scratches(patternUV * 2.2, wear);

    // fade modulates everything
    w     = mix(w, vec2(0.0), fade);
    w2    = mix(w2, vec2(0.0), fade);
    ridge = mix(ridge, vec2(0.0), fade);
    scr   = mix(scr, 0.0, fade);
    fiber *= mix(1.0, 0.5, fade);
    rough *= mix(1.0, 0.5, fade);

    normal += U_FOLDS * 4.0 * ridge;
    normal += U_ROUGHNESS * 1.5 * rough;
    normal += U_FIBER * fiber;
    normal -= U_SCRATCH * 3.0 * scr;

    // normal.z sets relief strength. This is the single most sensitive constant:
    // z=6 flattens N to ~(0.07,0.07,1.0) and the shading varies <1% — invisible.
    // Solved for ~5% luminance variation at STRENGTH=1 => z~1.8. (Reference uses
    // 9.5-9*pow(contrast,.1), i.e. ~1.1 at its default contrast.)
    vec3 N = normalize(vec3(normal, U_RELIEF_Z));
    // Light MUST have same-sign x and y. Each scalar layer is added to both
    // normal components, so normal.x == normal.y; a light like (-0.6, 0.8, ..)
    // makes those terms cancel (-0.4 + 0.53 = 0.13) and throws away ~80% of the
    // relief response. (1,2,1) matches the reference and does not cancel.
    vec3 lightDir = normalize(vec3(1.0, 2.0, 1.0));
    float shade = mix(0.90, 1.06, clamp(dot(N, lightDir), 0.0, 1.0));

    // ambient occlusion: creases sit in shadow
    float ao = 1.0 - U_AO * 0.12 * clamp(length(ridge) * 1.5, 0.0, 1.0);

    vec3 paperTone = vec3(0.925, 0.884, 0.804);
    float luma = dot(pixColor.rgb, vec3(0.299, 0.587, 0.114));
    // only light backgrounds get papered; dark UI/text passes through
    float blend = smoothstep(0.55, 0.85, luma);

    vec3 papered = pixColor.rgb * paperTone * shade * ao;
    vec3 result = mix(pixColor.rgb, papered, blend);

    // alpha 1.0: this is the final screen, and preserving a <1 alpha lets the
    // nested-test window composite the host wallpaper through the page
    fragColor = vec4(result, 1.0);
}
