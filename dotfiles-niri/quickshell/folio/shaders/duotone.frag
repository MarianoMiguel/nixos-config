#version 450
// Printed app icons (dock.icons = printed): the icon's luminance, gamma
// boosted so bright icons keep their contrast, mapped from one ink (dark) to
// the paper (light), as the desktop study's duotone filter does.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 lo;           // luminance 0
    vec4 hi;           // luminance 1
    float gamma;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
    float l = pow(clamp(dot(rgb, vec3(0.3, 0.59, 0.11)), 0.0, 1.0), gamma);
    fragColor = vec4(mix(lo.rgb, hi.rgb, l) * c.a, c.a) * qt_Opacity;
}
