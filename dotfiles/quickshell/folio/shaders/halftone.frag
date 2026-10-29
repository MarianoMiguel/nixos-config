#version 450
// A halftone screen (Widgets/Halftone.qml): round dots on a square pitch over
// a background, as the kit draws typed cells and dialog scrims. Dots print in
// at random as progress rises; solid floods the area pixel by pixel.
// Colors arrive premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;           // device pixels
    vec4 ink;
    vec4 back;
    float pitchPx;      // device pixels between dot centres
    float radius;       // device pixels
    float progress;     // share of dots printed
    float solid;        // share of pixels flooded with ink
    float seed;
};

float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 cell = floor(px / pitchPx);
    float d = distance(px, (cell + 0.5) * pitchPx);
    float dotA = 1.0 - smoothstep(radius - 0.35, radius + 0.35, d);
    dotA *= hash(cell + seed) < progress ? 1.0 : 0.0;
    float flood = hash(floor(px) + seed + 5.3) < solid ? 1.0 : 0.0;
    fragColor = mix(back, ink, max(dotA, flood)) * qt_Opacity;
}
