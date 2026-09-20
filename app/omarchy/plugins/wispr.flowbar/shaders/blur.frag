#version 440
// One separable Gaussian pass (9 linear taps ~= 17 texel kernel). Run twice,
// once with a horizontal texelStep and once vertical, over the backdrop
// snapshot. It runs when a snapshot arrives, not per frame.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texelStep;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    const float w0 = 0.2270270270, w1 = 0.3162162162, w2 = 0.0702702703;
    const float o1 = 1.3846153846, o2 = 3.2307692308;
    vec4 c = texture(source, qt_TexCoord0) * w0;
    c += texture(source, qt_TexCoord0 + texelStep * o1) * w1;
    c += texture(source, qt_TexCoord0 - texelStep * o1) * w1;
    c += texture(source, qt_TexCoord0 + texelStep * o2) * w2;
    c += texture(source, qt_TexCoord0 - texelStep * o2) * w2;
    fragColor = c * qt_Opacity;
}
