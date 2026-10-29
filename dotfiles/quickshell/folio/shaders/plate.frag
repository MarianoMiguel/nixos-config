#version 450
// Folio's plate: an Azure Folio print (any 2-color render; light variant)
// re-printed at screen resolution in any ink. The same algorithm as the
// workshop kit (workshop/studies/_kit/folio.js):
//   develop  dots arrive in random order       (develop 0..1)
//   dissolve one plate becomes another per dot (mixAB 0..1)
//   bleed    new colors soak in from a point   (radius, edge, origin)
//   breathe  the dither keeps moving, 24-frame loop at 9 fps (breathe = share of live dots)
//   moonlit  dark plates keep the picture's tones (invert, thin)

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    vec2 focusA;
    vec2 focusB;
    vec2 origin;
    vec4 paper0;
    vec4 ink0;
    vec4 paper1;
    vec4 ink1;
    float dotSize;
    float mixAB;
    float develop;
    float radius;
    float edge;
    float time;
    float breathe;
    float zoomA;
    float zoomB;
    float lift;
    float invert0;
    float invert1;
    float thin0;
    float thin1;
};

layout(binding = 1) uniform sampler2D sourceA;
layout(binding = 2) uniform sampler2D sourceB;

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }

// object-fit: cover around a focus point; span is the visible part of the plate.
vec2 cover(vec2 uv, vec2 size, vec2 focus, float zoom, out vec2 span) {
    float sr = res.x / res.y, tr = size.x / size.y;
    span = (sr > tr ? vec2(1.0, tr / sr) : vec2(sr / tr, 1.0)) / zoom;
    vec2 off = clamp(focus - span * 0.5, vec2(0.0), vec2(1.0) - span);
    return off + uv * span;
}

// Ink coverage from the light render: paper ~0.955 luminance, ink ~0.30.
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
// Near native size the plate prints its own Atkinson dots; smaller (or for
// moving dots) it is re-dithered from the footprint's tone, averaged by hand
// with nine taps because Qt does not guarantee mipmaps on these textures.
float coverage(sampler2D t, vec2 uv, float lod) {
    vec2 size = vec2(textureSize(t, 0));
    if (lod < 0.75) {
        float c = lum(texelFetch(t, ivec2(clamp(uv, 0.0, 0.9999) * size), 0).rgb);
        return step(0.5, clamp((0.955 - c) / 0.655, 0.0, 1.0));
    }
    vec2 step2 = exp2(lod) * 0.5 / size;
    float sum = 0.0;
    for (int i = -1; i <= 1; i++)
        for (int j = -1; j <= 1; j++)
            sum += lum(textureLod(t, uv + vec2(float(i), float(j)) * step2, 0.0).rgb);
    return smoothstep(0.1, 0.9, clamp((0.955 - sum / 9.0) / 0.655, 0.0, 1.0));
}

void main() {
    vec2 px = qt_TexCoord0 * res;               // device pixels, y down
    vec2 cell = floor(px / dotSize);
    vec2 center = (cell + 0.5) * dotSize;
    vec2 uv = center / res;

    float live = step(hash(cell + 41.7), breathe);
    float frame = mod(floor(time * 9.0), 24.0);
    float th = ign(cell + live * frame * vec2(17.0, 31.0));

    vec2 sizeA = vec2(textureSize(sourceA, 0)), sizeB = vec2(textureSize(sourceB, 0));
    vec2 spanA, spanB;
    vec2 uvA = cover(uv, sizeA, focusA, zoomA, spanA);
    vec2 uvB = cover(uv, sizeB, focusB, zoomB, spanB);
    float lodA = log2(max(1.0, sizeA.x * spanA.x / res.x * dotSize));
    float lodB = log2(max(1.0, sizeB.x * spanB.x / res.x * dotSize));
    if (live > 0.5) { lodA = max(lodA, 1.2); lodB = max(lodB, 1.2); }
    float covA = clamp(coverage(sourceA, uvA, lodA) - lift, 0.0, 1.0);
    float covB = clamp(coverage(sourceB, uvB, lodB) - lift, 0.0, 1.0);
    float reach = distance(center, origin) + (hash(cell + 9.7) - 0.5) * edge;
    float fresh = step(reach, radius);
    vec4 paper = mix(paper0, paper1, fresh);
    vec4 inkc = mix(ink0, ink1, fresh);
    float invert = mix(invert0, invert1, fresh);
    float thin = mix(thin0, thin1, fresh);

    // Normal plates print the picture's ink; moonlit ones print its paper,
    // thinned through the same ordered threshold so skies stay even, not grainy.
    float sel = step(hash(cell + 3.1), mixAB);
    float inkA = step(th, covA) * step(0.002, covA);
    float inkB = step(th, covB) * step(0.002, covB);
    float moonA = step(th, (1.0 - covA) * (1.0 - thin)) * step(0.002, 1.0 - covA);
    float moonB = step(th, (1.0 - covB) * (1.0 - thin)) * step(0.002, 1.0 - covB);
    float lit = mix(mix(inkA, inkB, sel), mix(moonA, moonB, sel), invert);
    lit *= step(hash(cell + 17.3), develop);
    fragColor = mix(paper, inkc, lit) * qt_Opacity;
}
