#version 450
// Develop for interface items (Widgets/Develop.qml): the item prints in dot
// by dot as progress goes 0 -> 1 and lifts off going back, the same random
// threshold the plates develop with. invert keeps the dots not yet printed,
// so two items with the same seed swap without a gap (a clock's new minute).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;           // device pixels
    float progress;     // share of dots printed
    float dotSize;      // device pixels per dot
    float seed;
    float invert;
};

layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }

void main() {
    vec2 cell = floor(qt_TexCoord0 * res / dotSize);
    float on = hash(cell + seed) < progress ? 1.0 : 0.0;
    on = mix(on, 1.0 - on, invert);
    fragColor = texture(source, qt_TexCoord0) * on * qt_Opacity;
}
