// Shaders for Personalizza's surfaces. Colours reach these premultiplied by
// alpha, and every function keeps them that way.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A stable per-pixel random value in [0, 1).
static float hash21(float2 point, float seed) {
    return fract(sin(dot(point, float2(12.9898, 78.233)) + seed) * 43758.5453);
}

// Film grain: each point lightened or darkened a little, the same on every
// frame, so the page reads as printed rather than as flickering noise.
[[ stitchable ]] half4 paperGrain(float2 position, half4 color, float amount, float seed) {
    float noise = hash21(floor(position), seed) - 0.5;
    half shift = half(noise * amount);
    return half4(clamp(color.rgb + shift * color.a, 0.0h, color.a), color.a);
}

// Paper fibre: grain plus faint long streaks, like a sheet of drawing paper.
[[ stitchable ]] half4 paperFibre(float2 position, half4 color, float amount) {
    float grain = hash21(floor(position), 3.1) - 0.5;
    float streak = sin(position.x * 0.07 + sin(position.y * 0.013) * 9.0) * 0.5;
    half shift = half((grain * 0.7 + streak * 0.3) * amount);
    return half4(clamp(color.rgb + shift * color.a, 0.0h, color.a), color.a);
}

// A cut-out edge around whatever is drawn: transparent points near opaque
// ones take the outline colour, as a printed sticker's white border.
[[ stitchable ]] half4 stickerOutline(float2 position, SwiftUI::Layer layer, float radius, half4 outline) {
    half4 here = layer.sample(position);
    if (here.a > 0.99h) {
        return here;
    }
    half reach = 0.0h;
    for (int ring = 1; ring <= 2; ring++) {
        float distance = radius * float(ring) / 2.0;
        for (int step = 0; step < 16; step++) {
            float angle = float(step) / 16.0 * 6.2831853;
            half4 neighbour = layer.sample(position + float2(cos(angle), sin(angle)) * distance);
            reach = max(reach, neighbour.a);
        }
    }
    half4 edge = outline * smoothstep(0.1h, 0.6h, reach);
    return here + edge * (1.0h - here.a);
}

// Three colours drifting as soft blobs: the moving face of a Flavor.
[[ stitchable ]] half4 flavorFlow(float2 position, half4 color, float2 size, float time,
                                  half4 main, half4 accent, half4 extra) {
    float2 uv = position / max(size, float2(1.0));
    float2 p1 = float2(0.22 + 0.16 * sin(time * 0.70), 0.30 + 0.22 * cos(time * 0.50));
    float2 p2 = float2(0.78 + 0.14 * cos(time * 0.60), 0.35 + 0.20 * sin(time * 0.80));
    float2 p3 = float2(0.50 + 0.26 * sin(time * 0.45), 0.90 + 0.10 * cos(time * 0.90));
    float w1 = 1.0 / (0.015 + dot(uv - p1, uv - p1));
    float w2 = 1.0 / (0.015 + dot(uv - p2, uv - p2));
    float w3 = 1.0 / (0.015 + dot(uv - p3, uv - p3));
    half3 mixed = (main.rgb * half(w1) + accent.rgb * half(w2) + extra.rgb * half(w3)) / half(w1 + w2 + w3);
    return half4(mixed * color.a, color.a);
}

// A glossy button's light: a bright band from the top, a soft shade at the
// bottom, as on a rounded, lacquered surface.
[[ stitchable ]] half4 glossSheen(float2 position, half4 color, float2 size, float strength) {
    float y = position.y / max(size.y, 1.0);
    half highlight = half(smoothstep(0.55, 0.0, y) * 0.32 * strength);
    half shade = half(smoothstep(0.55, 1.0, y) * 0.14 * strength);
    half3 lit = color.rgb + (color.a - color.rgb) * highlight - color.rgb * shade;
    return half4(clamp(lit, 0.0h, color.a), color.a);
}
