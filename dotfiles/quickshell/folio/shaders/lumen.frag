#version 450
// Lumen's wallpaper, drawn at any size from the theme's color
// (Widgets/Plate passes the colors; packages/plymouth-folio/build.py draws
// the same skies for the disk-unlock screen). Three styles:
//   0 prism  ribbons of light seen through fluted glass
//   1 glow   one soft luminous shape
//   2 haze   a full-bleed gradient
// Light adds on the field and is tone-mapped, so cores whiten like real
// light; night fields are near black, day fields a pale grey.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    vec4 field;     // the background
    vec4 light0;    // the accent's hue
    vec4 light1;    // and three neighbours, toward violet and pink
    vec4 light2;
    vec4 light3;
    float style;
    float night;
    float develop;
    float dotSize;
};

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// At night light adds to the field and is tone-mapped, so cores whiten like
// real light. By day it is laid on as colour: the light's own hue at full
// strength, as much of it as the light is bright.
vec3 expose(vec3 base, vec3 light, float exposure) {
    if (night > 0.5) return base + (vec3(1.0) - base) * (vec3(1.0) - exp(-light * exposure));
    float peak = max(max(light.r, light.g), light.b);
    vec3 tint = mix(light / max(peak, 1e-3) * 0.9, vec3(1.0), 0.12);
    return mix(base, tint, (1.0 - exp(-peak * exposure)) * 0.88);
}

// Prism: three ribbons sweeping up to the right, each brightening and
// fading along its length, so light gathers in places and black stays black.
vec3 ribbons(vec2 p, float aspect) {
    vec3 sum = vec3(0.0);
    float x = p.x / aspect;
    vec3 tones[3] = vec3[3](light0.rgb, light1.rgb, light2.rgb);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float y = 1.02 - 0.92 * x + 0.06 * sin(x * 3.3 + fi * 2.3) + (fi - 1.0) * 0.085;
        float w = 0.045 + 0.018 * fi;
        float d = p.y - y;
        float along = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(x * 5.1 + fi * 1.9 + 0.6), 1.6);
        sum += tones[i] * exp(-d * d / (2.0 * w * w)) * along * (1.3 - 0.25 * fi);
    }
    // A low warm ember along the lower edge of the swath.
    float d3 = p.y - (1.16 - 0.92 * x);
    sum += light3.rgb * 0.5 * exp(-d3 * d3 / (2.0 * 0.05 * 0.05)) * smoothstep(0.25, 0.85, x);
    return sum;
}

vec3 prism(vec2 uv, float aspect) {
    vec2 p = vec2(uv.x * aspect, uv.y);
    // Fluted glass: diagonal bands, each refracting what is behind it.
    float ang = radians(-40.0);
    mat2 rot = mat2(cos(ang), -sin(ang), sin(ang), cos(ang));
    vec2 q = rot * p;
    float width = 0.2;
    float band = floor(q.x / width);
    float t = fract(q.x / width);
    vec2 shift = transpose(rot) * vec2((t - 0.5) * width * 1.4, (t - 0.5) * 0.05 + sin(band * 2.7) * 0.02);
    vec3 light = ribbons(p + shift, aspect);
    // Each band is lit toward its far edge; the edge catches what is behind it.
    light *= 0.55 + 0.75 * t * t;
    light += light * 0.9 * smoothstep(0.95, 1.0, t);
    return expose(field.rgb, light, night > 0.5 ? 1.15 : 0.9);
}

// Glow: a few lobes merged into one shape with a soft but definite edge,
// its core near white, a faint halo of its rim's colour around it.
vec3 glow(vec2 uv, float aspect) {
    vec2 p = vec2(uv.x * aspect, uv.y);
    vec2 c = vec2(aspect * 0.56, 0.47);
    vec2 a = p - c - vec2(-0.15, 0.03), b = p - c - vec2(0.11, -0.07), e = p - c - vec2(0.06, 0.11);
    float f = exp(-dot(a, a) / 0.026) + exp(-dot(b, b) / 0.03) + 0.85 * exp(-dot(e, e) / 0.02);
    float body = smoothstep(0.42, 0.78, f);
    float core = smoothstep(0.75, 1.5, f);
    float halo = exp(-length(p - c) / 0.2) * (1.0 - body);
    vec3 light = light1.rgb * body * 1.25 + light2.rgb * halo * 0.4 + mix(light0.rgb, vec3(1.0), night > 0.5 ? 0.7 : 0.25) * core * 1.5;
    return expose(field.rgb, light, night > 0.5 ? 1.6 : 1.1);
}

// Haze: deep warmth top left, peach low left, violet through the middle,
// the accent and a cool lift on the right.
vec3 haze(vec2 uv, float aspect) {
    vec3 warmDeep = light3.rgb * (night > 0.5 ? 0.55 : 0.8);
    vec3 peach = mix(light3.rgb, vec3(1.0, 0.82, 0.68), 0.45);
    vec3 cool = mix(light0.rgb, vec3(0.55, 0.85, 1.0), 0.35);
    vec3 top = mix(warmDeep, light1.rgb, smoothstep(0.0, 0.75, uv.x));
    top = mix(top, light0.rgb, smoothstep(0.6, 1.0, uv.x));
    vec3 bottom = mix(peach, light2.rgb, smoothstep(0.0, 0.5, uv.x));
    bottom = mix(bottom, cool, smoothstep(0.5, 1.0, uv.x));
    vec3 col = mix(top, bottom, smoothstep(0.0, 1.0, uv.y));
    return night > 0.5 ? col * 0.78 : mix(col, vec3(1.0), 0.12);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    vec3 col = style < 0.5 ? prism(uv, aspect) : style < 1.5 ? glow(uv, aspect) : haze(uv, aspect);
    // Half a step of noise hides banding in the long gradients.
    col += (hash(uv * res) - 0.5) / 255.0;
    col = mix(field.rgb, col, develop);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
