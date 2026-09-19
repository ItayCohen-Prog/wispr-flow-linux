#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float cornerRadius;
    float padding;
    vec4 tint;
    float emphasis;
};

float roundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void over(inout vec4 dst, vec3 color, float alpha) {
    dst = vec4(color * alpha, alpha) + dst * (1.0 - alpha);
}

void main() {
    vec2 halfSize = size * 0.5 - padding;
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    float r = min(cornerRadius, min(halfSize.x, halfSize.y));
    float d = roundedBox(p, halfSize, r);
    float aa = max(fwidth(d), 0.7);
    float inside = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);
    float depth = max(-d, 0.0);

    // One analytic pass: no texture capture, offscreen layer or animation clock.
    // Shadow alpha stays below the compositor's 0.2 blur cutoff.
    float sd = roundedBox(p - vec2(0.0, 4.0), halfSize, r);
    float shadow = step(0.5, padding) * 0.18 * exp(-max(sd, 0.0) / 4.5) * (1.0 - inside);
    vec4 result = vec4(vec3(0.04, 0.05, 0.08) * shadow, shadow);
    // QColor uniforms arrive premultiplied; over() takes straight RGB.
    over(result, tint.rgb / max(tint.a, 0.0001), tint.a * inside);

    vec2 q = abs(p) - halfSize + r;
    vec2 n = q.x > 0.0 || q.y > 0.0 ? normalize(max(q, 0.0) + 0.0001) :
             (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    n *= sign(p);
    float light = dot(n, normalize(vec2(-0.65, -0.76)));
    float highlight = 0.22 + 0.58 * pow(max(light, 0.0), 2.0)
                           + 0.36 * pow(max(-light, 0.0), 6.0);
    // A broad bevel, a recessed inner edge, and a narrow polished lip.
    float bevel = exp(-depth / 3.2);
    float recess = exp(-pow((depth - 3.0) / 2.0, 2.0));
    over(result, vec3(0.10, 0.13, 0.20), recess * 0.20 * inside);
    over(result, vec3(0.93, 0.97, 1.0), bevel * highlight * 0.52 * inside);
    float lip = exp(-pow((depth - 0.65) / 0.65, 2.0));
    over(result, vec3(1.0), lip * highlight * 0.90 * inside);
    float top = exp(-(p.y + halfSize.y) / 12.0);
    over(result, vec3(1.0), (0.12 * top + emphasis * 0.08) * inside);
    fragColor = result * qt_Opacity;
}
