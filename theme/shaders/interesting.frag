#version 300 es
// "Interesting" -- screen-shader port of the paperlab preset the user tuned
// (presets/Interesting.json). Character: VERTICAL directional grain (cockle
// md -90, anisotropy 6), Gabor-ish formation mottle, STRONG specular gloss,
// cool-blue shadow / warm highlight duotone, sparse light scratches. Luma-gated:
// papers light regions, leaves text/UI alone. Static -> no shimmer.
precision highp float;
precision highp int;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

uvec2 pcg2d(uvec2 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u; v ^= v >> 16u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u; v ^= v >> 16u;
    return v;
}
float hash21(ivec2 p) { return float(pcg2d(uvec2(p)).x) * (1.0 / 4294967295.0); }
float valueNoise(vec2 st) {
    ivec2 i = ivec2(floor(st)); vec2 f = fract(st);
    float a = hash21(i), b = hash21(i + ivec2(1, 0));
    float c = hash21(i + ivec2(0, 1)), d = hash21(i + ivec2(1, 1));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
const mat2 ROT = mat2(0.7648, -0.6442, 0.6442, 0.7648);
float fbm(vec2 n) {
    float t = 0.0, amp = 1.0, tot = 0.0;
    for (int i = 0; i < 4; i++) { n = ROT * n; t += valueNoise(n) * amp; tot += amp; n *= 2.0; amp *= 0.55; }
    return t / tot;
}

// VERTICAL cockle: md -90 => crests run vertically => the field varies fast in x,
// slow in y. anisotropy 6 => stretch y. wavelength 5mm. Plus a subtle crumple.
float heightAt(vec2 mm) {
    vec2 t = mm; t.y /= 6.0;                                  // vertical crests, aniso 6
    float cockle  = (fbm(t / (5.0 * 0.55)) - 0.5) * 0.020;    // fine vertical grain
    float crumple = (fbm(mm / (8.5 * 0.55)) - 0.5) * 0.012;   // subtle isotropic lumps
    return cockle + crumple;
}

void main() {
    vec2 res = vec2(textureSize(tex, 0));
    vec3 src = texture(tex, v_texcoord).rgb;
    float luma = dot(src, vec3(0.299, 0.587, 0.114));
    float gate = smoothstep(0.55, 0.85, luma);
    if (gate <= 0.001) { fragColor = vec4(src, 1.0); return; }

    float pxmm = res.x / 216.0;
    vec2 mm = (v_texcoord * res) / pxmm;

    // normal from the height gradient
    float st = 0.4;
    float hx = heightAt(mm + vec2(st, 0.0)) - heightAt(mm - vec2(st, 0.0));
    float hy = heightAt(mm + vec2(0.0, st)) - heightAt(mm - vec2(0.0, st));
    float rz = 9.0;                                          // relief exaggerate (preset 6, +gloss)
    vec3 N = normalize(vec3(-hx * rz / (2.0 * st), -hy * rz / (2.0 * st), 1.0));

    // light: azimuth 130, altitude 65 (above, slightly left)
    vec3 L = normalize(vec3(-0.27, 0.32, 0.91));
    float shade = clamp(0.96 + 1.0 * (dot(N, L) - L.z), 0.87, 1.08);

    // STRONG specular gloss (preset spec_intensity 1.34, power 35) -- the glints
    // that catch the vertical grain and make it read as "interesting".
    vec3 V = vec3(0.0, 0.0, 1.0);
    vec3 H = normalize(L + V);
    float spec = pow(max(dot(N, H), 0.0), 35.0) * 0.9;

    // cavity/AO
    float blur = 0.0;
    for (int k = 0; k < 4; k++) { float a = float(k) * 1.5707963; blur += heightAt(mm + vec2(cos(a), sin(a)) * 1.5); }
    blur *= 0.25;
    shade -= 0.10 * clamp((blur - heightAt(mm)) * 55.0, 0.0, 1.0);

    // formation mottle (preset: Gabor, 2.4mm, amp .024) + fine tooth
    float form  = (fbm(mm / 2.4) - 0.5) * 0.030;
    float tooth = (fbm(mm / 0.5) - 0.5) * 0.030;

    // non-stationary fade (preset amount .51, 85mm)
    float fade = clamp(8.0 * pow(fbm(mm / 85.0), 3.0), 0.0, 1.0) * 0.51;

    // sparse LIGHT scratches (preset density .087, scale 8mm, lightness .16)
    float scr = 0.0;
    vec2 cell = mm / 8.0;
    ivec2 ci = ivec2(floor(cell));
    if (hash21(ci * 3 + 5) > 0.913) {
        vec2 f = fract(cell) - 0.5;
        float ang = hash21(ci * 7 + 11) * 3.14159;
        vec2 dir = vec2(cos(ang), sin(ang));
        float perp = f.x * -dir.y + f.y * dir.x;
        float along = f.x * dir.x + f.y * dir.y;
        scr = (1.0 - smoothstep(0.0, 0.03, abs(perp))) * (1.0 - smoothstep(0.3, 0.5, abs(along))) * 0.16;
    }

    // cool-blue shadow / warm highlight duotone (preset duotone .35, deep-blue shadow)
    float s = shade - 1.0;
    vec3 warm = mix(vec3(1.0), vec3(1.02, 1.00, 0.96), clamp(s * 4.0, 0.0, 1.0) * 0.35);
    vec3 cool = mix(vec3(1.0), vec3(0.55, 0.72, 1.05), clamp(-s * 4.0, 0.0, 1.0) * 0.35);
    vec3 duo = warm * cool;

    vec3 cream = vec3(1.0, 0.953, 0.871);
    vec3 paper = cream * shade * (1.0 + form + tooth - fade * 0.15 + scr) * duo + spec * vec3(1.0, 0.99, 0.95);

    vec3 outc = src * mix(vec3(1.0), paper, gate);
    fragColor = vec4(clamp(outc, 0.0, 1.0), 1.0);
}
