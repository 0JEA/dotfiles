#version 300 es
// paperlab-derived screen shader: ports paperlab's LIT surface into a Hyprland
// screen shader -- cream + lit cockle relief (procedural height -> normal ->
// above-left shading) + gentle formation, luma-gated so it papers light regions
// (PDF pages) and leaves text / dark UI alone. Unlike the flat tint+grain shader,
// this has real relief lighting -> depth. Static (never animates -> no shimmer).
precision highp float;
precision highp int;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

// --- PCG2D hash (Jarzynski & Olano) -- avoids the grid artifacts of sin/fract.
uvec2 pcg2d(uvec2 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v ^= v >> 16u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v ^= v >> 16u;
    return v;
}
float hash21(ivec2 p) { return float(pcg2d(uvec2(p)).x) * (1.0 / 4294967295.0); }

float valueNoise(vec2 st) {
    ivec2 i = ivec2(floor(st));
    vec2  f = fract(st);
    float a = hash21(i), b = hash21(i + ivec2(1, 0));
    float c = hash21(i + ivec2(0, 1)), d = hash21(i + ivec2(1, 1));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
const mat2 ROT = mat2(0.7648, -0.6442, 0.6442, 0.7648);
float fbm(vec2 n) {                         // ~0..1
    float t = 0.0, amp = 1.0, tot = 0.0;
    for (int i = 0; i < 4; i++) { n = ROT * n; t += valueNoise(n) * amp; tot += amp; n *= 2.0; amp *= 0.55; }
    return t / tot;
}

// cockle height in mm. Anisotropic organic buckling (crests along MD, x). Two
// bands: a broad 28mm undulation (the big sweeps) PLUS a 7mm mid band that gives
// VISIBLE local relief -- a single broad band varies too slowly to read on screen.
float heightAt(vec2 mm) {
    vec2 t = mm; t.x /= 1.2;                            // near-isotropic (no horizontal streak)
    float broad = (fbm(t / (24.0 * 0.55)) - 0.5) * 0.034;   // 34um, 24mm
    float mid   = (fbm(t / (6.0  * 0.55)) - 0.5) * 0.022;   // 22um, 6mm (visible)
    return broad + mid;
}

void main() {
    vec2 res = vec2(textureSize(tex, 0));
    vec3 src = texture(tex, v_texcoord).rgb;
    float luma = dot(src, vec3(0.299, 0.587, 0.114));

    // gate: only paper the light regions (page), leave text / dark UI untouched
    float gate = smoothstep(0.55, 0.85, luma);
    if (gate <= 0.001) { fragColor = vec4(src, 1.0); return; }

    float pxmm = res.x / 216.0;              // assume the page ~ Letter width fills x
    vec2 mm = (v_texcoord * res) / pxmm;

    // lit cockle relief: normal from the height gradient (finite diff), above-left light
    float st = 0.45;                         // mm sampling step for the gradient
    float hx = heightAt(mm + vec2(st, 0.0)) - heightAt(mm - vec2(st, 0.0));
    float hy = heightAt(mm + vec2(0.0, st)) - heightAt(mm - vec2(0.0, st));
    float rz = 6.0;                          // relief exaggeration (slopes are tiny)
    vec3 N = normalize(vec3(-hx * rz / (2.0 * st), -hy * rz / (2.0 * st), 1.0));
    vec3 L = normalize(vec3(-0.42, 0.42, 0.80));   // above-left ~26deg, alt ~50
    // centre a FLAT area at 0.96 (proper cream, not blown to white); relief tilts
    // N so dot(N,L) moves off L.z, modulating the shade GENTLY around that.
    float shade = clamp(0.96 + 1.0 * (dot(N, L) - L.z), 0.87, 1.08);

    // cavity/AO: blur(h) - h, darken the pits a touch (the emboss-escape)
    float blur = 0.0;
    for (int k = 0; k < 4; k++) {
        float a = float(k) * 1.5707963;
        blur += heightAt(mm + vec2(cos(a), sin(a)) * 1.2);
    }
    blur *= 0.25;
    float cav = clamp((blur - heightAt(mm)) * 60.0, 0.0, 1.0);
    shade -= 0.10 * cav;

    // formation (mass mottle) + a fine EVEN isotropic tooth (the immediate 'paper'
    // feel) + a finer micro-grain. Stronger than before -- the effect read too light.
    float form  = (fbm(mm / 2.6) - 0.5) * 0.028;
    float tooth = (fbm(mm / 0.5) - 0.5) * 0.045;
    float micro = (valueNoise(mm / 0.2) - 0.5) * 0.032;

    // warm/cool: warm the highlights, cool the pits (painter's rule) -- gentle & capped
    vec3 warm = vec3(1.02, 1.00, 0.97), cool = vec3(0.97, 0.98, 1.02);
    vec3 duo = mix(vec3(1.0), (shade > 1.0) ? warm : cool, clamp(abs(shade - 1.0) * 2.5, 0.0, 0.35));

    vec3 cream = vec3(1.0, 0.945, 0.855);    // richer cream (calm reads deeper)
    vec3 paper = cream * shade * (1.0 + form + tooth + micro) * duo;

    // apply to light regions only (multiply the page toward cream*shade), text kept
    vec3 outc = src * mix(vec3(1.0), paper, gate);
    fragColor = vec4(clamp(outc, 0.0, 1.0), 1.0);
}
