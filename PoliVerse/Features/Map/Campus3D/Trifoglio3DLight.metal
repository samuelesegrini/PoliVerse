// PROTOTYPE — the 3D walk's baked light, for `Trifoglio3DTuning.bakedLight`.
//
// RealityKit's physically based lighting costs the GPU about 4 ms a frame on an iPhone 12 Pro
// at the campus view, a quarter of the 16.7 ms a 60 Hz frame has. The walk's light never moves:
// a sun and a weaker fill from fixed directions, and the sky. This surface shader gives each
// pixel the same light from its normal with a handful of multiplications, under an unlit material.
//
// The weights are fitted on the phone (`banco/luce.py`): screenshots of the campus lit by
// RealityKit, of its base colours and of its normals, read back through RealityKit's tone curve
// (measured on plain greys), and a least-squares fit of the first against the other two.

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

/// The scene's base colour lit by the walk's fixed light. The custom parameter's x scales the
/// light (1: as fitted). For the fit: x below 0 draws the normals, y above 0 the base colour
/// times x, z above 0 the plain grey x.
[[visible]]
void trifoglio3dBakedLight(realitykit::surface_parameters params)
{
    constexpr sampler linear(filter::linear, mip_filter::linear, address::repeat);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    float3 albedo = float3(params.material_constants().base_color_tint())
        * float3(params.textures().base_color().sample(linear, uv).rgb);
    float3 n = normalize(params.geometry().normal());
    float4 k = params.uniforms().custom_parameter();

    float3 color;
    if (k.x < 0) {
        color = 0.5 + 0.5 * n;
    } else if (k.z > 0) {
        color = k.x;
    } else if (k.y > 0) {
        color = albedo * k.x;
    } else {
        // Towards the lights, as Trifoglio3DScene.load(into:) aims them at (20, 0, 140).
        const float3 sun = normalize(float3(-180, 260, 80));
        const float3 fill = normalize(float3(200, 180, -260));
        // Second-order spherical harmonics of the sky and the two lights, plus their direct part,
        // in the light before RealityKit's tone curve, which both pictures go through.
        float light = 0.6172 - 0.0112 * n.x + 0.0581 * n.y + 0.2503 * n.z
            + 0.2562 * n.x * n.y + 0.1034 * n.y * n.z + 0.162 * n.x * n.z
            - 0.1278 * (n.x * n.x - n.z * n.z) - 0.0609 * (3 * n.y * n.y - 1)
            + 1.6138 * max(0.0, dot(n, sun)) + 0.6341 * max(0.0, dot(n, fill));
        color = albedo * light * k.x;
    }
    params.surface().set_base_color(half3(color));
    params.surface().set_emissive_color(half3(color));
    params.surface().set_opacity(half(params.material_constants().opacity_scale()));
}
