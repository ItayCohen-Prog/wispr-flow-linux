#version 440
// Liquid glass. Refracts a snapshot of the desktop through a squircle bevel
// at the rim (exact Snell, IOR 1.5), frosts the interior, applies an
// adaptive light or dark tint, and lights the rim from the top left.
// Numbers follow pixel measurements of iOS 26 glass: dark body 0x37 at
// 0.36, a 1-2 px directional edge line, rim displacement outward, blue
// dispersed further than red.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // item size, logical px
    vec2 shapeHalf;     // half size of the drawn shape, centred in the item
    float cornerRadius;
    float form;         // 0 forming .. 1 settled
    float emphasis;     // hover/press lift
    float darkness;     // 0 light glass .. 1 dark glass
    float frost;        // interior blur amount 0..1
    float warmth;       // error tint 0..1
    vec2 texOrigin;     // item (0,0) inside the backdrop textures, logical px
    vec2 texSize;       // backdrop texture coverage, logical px
};
layout(binding = 1) uniform sampler2D sharpTex;
layout(binding = 2) uniform sampler2D frostTex;

const float BAND = 14.0;       // rim lens width, px
const float RIM_SHIFT = 9.0;   // displacement at the rim, px
const float IOR = 1.5;
const float BEVEL_POWER = 4.0; // squircle bevel
const float SPLIT = 0.05;     // dispersion
const float BEVEL = 2.5;       // highlight band, px
const float DOME = 0.25;
const float MAG = 0.03;

float sdRoundBox(vec2 p, vec2 h, float r) {
    vec2 q = abs(p) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
vec2 gradRoundBox(vec2 p, vec2 h, float r) {
    vec2 q = abs(p) - h + r;
    vec2 g = (q.x > 0.0 || q.y > 0.0) ? normalize(max(q, 0.0) + 1e-5)
                                       : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    return g * sign(p + vec2(1e-6));
}
float bevelSlope(float e) {
    e = clamp(e, 0.002, 0.998);
    float u = 1.0 - e;
    return pow(u, BEVEL_POWER - 1.0) / pow(1.0 - pow(u, BEVEL_POWER), 1.0 - 1.0 / BEVEL_POWER);
}
// tan(i - t) for a surface with slope s: the lateral shift per unit depth.
float snellShift(float s) {
    float ci = inversesqrt(1.0 + s * s);
    float si = s * ci;
    float st = si / IOR;
    float ct = sqrt(max(1.0 - st * st, 0.0));
    return (si * ct - ci * st) / (ci * ct + si * st);
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec2 uvAt(vec2 px) { return clamp((texOrigin + px) / texSize, vec2(0.0), vec2(1.0)); }

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 centre = size * 0.5;
    vec2 p = px - centre;
    vec2 h = shapeHalf;
    float r = min(cornerRadius, min(h.x, h.y));
    float sd = sdRoundBox(p, h, r);
    float coverage = 1.0 - smoothstep(-0.75, 0.75, sd);

    // Drop shadow, outside the shape only. Deeper while the glass is thick.
    float sds = sdRoundBox(p - vec2(0.0, 5.0), h, r);
    float shadowA = (0.16 + 0.10 * darkness) * form * exp(-max(sds, 0.0) / 10.0) * (1.0 - coverage);
    vec4 result = vec4(0.0, 0.0, 0.0, shadowA);
    if (coverage <= 0.0) { fragColor = result * qt_Opacity; return; }

    float depth = max(-sd, 0.0);
    // Normal: closed form with a widened corner so the caps have no crease,
    // plus a dome term so straight edges curve too.
    float gr = min(1.5 * r, min(h.x, h.y));
    vec2 n = normalize(gradRoundBox(p, h, gr) + DOME * normalize(p / h + vec2(1e-5)));
    // The semicircular caps get a wider band: the roundness shows there.
    float capW = smoothstep(h.x - r - BAND, h.x - r, abs(p.x));
    float band = BAND * mix(1.0, 1.35, capW) * mix(1.4, 1.0, form);
    float e = clamp(depth / band, 0.0, 1.0);
    float s = bevelSlope(e);
    float bend = snellShift(s) / snellShift(bevelSlope(0.0));
    bend *= smoothstep(1.0, 0.75, e) * smoothstep(0.0, 1.5, depth);
    float shift = RIM_SHIFT * mix(1.0, 1.35, capW) * mix(1.6, 1.0, form);
    vec2 push = n * bend * shift - p * MAG * (1.0 - e);

    // Backdrop: sharp at the rim with dispersion, frosted inside.
    float cr = 1.0 - SPLIT * bend, cb = 1.0 + SPLIT * bend;
    vec3 sharp = vec3(texture(sharpTex, uvAt(px + push * cr)).r,
                      texture(sharpTex, uvAt(px + push)).g,
                      texture(sharpTex, uvAt(px + push * cb)).b);
    vec3 soft = vec3(texture(frostTex, uvAt(px + push * cr)).r,
                     texture(frostTex, uvAt(px + push)).g,
                     texture(frostTex, uvAt(px + push * cb)).b);
    // Uniform frost across the shape; the lens only bends it at the rim.
    vec3 bg = mix(sharp, soft, frost);
    bg = mix(vec3(luma(bg)), bg, mix(1.35, 1.2, darkness));

    // Adaptive material: one decision per element (darkness uniform).
    vec3 tintC = mix(vec3(0.975, 0.970, 0.955), vec3(0.216), darkness);
    tintC = mix(tintC, vec3(0.62, 0.26, 0.12), warmth * 0.5);
    float tintA = mix(0.30, 0.36, darkness);
    vec3 col = mix(bg, tintC, clamp(tintA, 0.0, 0.6));
    col += vec3(0.06) * emphasis;

    // Rim light from the top left, a softer counter light opposite.
    vec2 L = normalize(vec2(-0.45, -0.89));
    float facing = dot(n, L);
    float bevelBand = smoothstep(BEVEL, 0.0, depth);
    float key = pow(max(facing, 0.0), 6.0) * bevelBand;
    float counter = pow(max(-facing, 0.0), 8.0) * bevelBand * 0.8;
    float edge = smoothstep(1.6, 0.0, depth);
    float edgeLine = edge * 0.5 * (max(facing, 0.0) + 0.8 * max(-facing, 0.0));
    float cosI = inversesqrt(1.0 + s * s);
    float fres = (0.04 + 0.96 * pow(1.0 - cosI, 5.0)) * bevelBand * 0.10;
    float sheen = 0.13 * pow(max(facing, 0.0), 2.5) * smoothstep(band * 0.7, 0.0, depth);
    col += vec3(1.0) * (0.45 * (key + counter) + 0.65 * edgeLine + fres + sheen);
    col -= vec3(0.07) * edge * (1.0 - abs(facing));
    col -= vec3(0.05) * max(smoothstep(2.2 * BEVEL, 0.0, depth) - bevelBand, 0.0);
    col = clamp(col, 0.0, 1.0);

    result = vec4(col * coverage, coverage) + result * (1.0 - coverage);
    fragColor = result * qt_Opacity;
}
