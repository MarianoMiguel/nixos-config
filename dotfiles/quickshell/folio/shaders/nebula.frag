#version 450
// Lumen's wallpaper: a nebula in the hues around the theme's accent, drawn
// procedurally at any size (the same picture as nebula() in
// workshop/studies/interstellar/v1.html). A sky gradient, four soft glows,
// fine stars at night, and a little noise so the gradients never band.
// Widgets/Plate uses it in place of Folio's plate when the theme is Lumen.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    vec4 sky0;
    vec4 sky1;
    vec4 glow0;
    vec4 glow1;
    vec4 glow2;
    vec4 glow3;
    float stars;
    float develop;
    float dotSize;
};

// Dave Hoskins' hash12: no lattice at any scale.
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// A glow centred at c (in units of the height), radius r (in units of the
// width, as the study draws it), strength in the colour's alpha.
vec3 glow(vec3 col, vec2 p, float aspect, vec2 c, float r, vec4 g) {
    vec2 d = p - vec2(c.x * aspect, c.y);
    float k = exp(-dot(d, d) / (2.0 * pow(r * aspect * 0.42, 2.0)));
    // Qt hands colors to shaders premultiplied by their alpha.
    vec3 hue = g.a > 0.0 ? g.rgb / g.a : g.rgb;
    return mix(col, hue, g.a * k);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);

    vec3 col = mix(sky0.rgb, sky1.rgb, uv.y);
    col = glow(col, p, aspect, vec2(0.22, 0.34), 0.42, glow0);
    col = glow(col, p, aspect, vec2(0.78, 0.58), 0.38, glow1);
    col = glow(col, p, aspect, vec2(0.52, 1.02), 0.46, glow2);
    col = glow(col, p, aspect, vec2(0.92, 0.08), 0.22, glow3);

    if (stars > 0.0) {
        // One star in about four hundred cells of two device pixels.
        vec2 px = uv * res / (2.0 * dotSize);
        vec2 cell = floor(px);
        float h = hash(cell);
        if (h > 0.9975) {
            float b = hash(cell + 7.31);
            float big = step(0.94, b);
            float r = mix(0.32, 0.62, big);
            float d = length(fract(px) - 0.5);
            col += vec3(stars * (0.15 + 0.6 * b) * (1.0 - smoothstep(r * 0.4, r, d)));
        }
    }

    // Half a step of noise hides banding in the long gradients.
    col += (hash(uv * res) - 0.5) / 255.0;
    // Develop: the first appearance rises out of the sky's base colour.
    col = mix(sky0.rgb, col, develop);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
