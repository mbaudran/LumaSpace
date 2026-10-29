// Compiled at runtime with MTLDevice.makeLibrary(source:), like shaderSource.
let cinemaShaderSource = """
#include <metal_stdlib>
using namespace metal;

// Packed by CinemaRenderer.uniforms(): matrix, 8 light positions, 8 light normals, then params.
struct CinemaUniforms {
    float4x4 viewProj;
    float4 lightPos[8];
    float4 lightNormal[8];
    float ambient;
    float gain;
    float falloff;
    float pad;
};

struct RoomOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 albedo;
};

// 9 floats per vertex: position, normal, albedo.
vertex RoomOut roomVertex(uint vid [[vertex_id]], const device float *v [[buffer(0)]],
                          constant CinemaUniforms &u [[buffer(1)]]) {
    uint b = vid * 9;
    RoomOut o;
    o.world = float3(v[b], v[b + 1], v[b + 2]);
    o.normal = float3(v[b + 3], v[b + 4], v[b + 5]);
    o.albedo = float3(v[b + 6], v[b + 7], v[b + 8]);
    o.position = u.viewProj * float4(o.world, 1.0);
    return o;
}

// Lit by ambient plus 8 samples across the screen, each glowing with that part of the picture.
fragment float4 roomFragment(RoomOut in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                             texture2d<float> light [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float3 n = normalize(in.normal);
    float3 c = u.ambient * in.albedo;
    for (int i = 0; i < 8; i++) {
        float3 L = u.lightPos[i].xyz - in.world;
        float d = max(length(L), 0.01);
        float3 l = L / d;
        // Mostly direct light, plus a little that ignores the surface's direction (bounce), so seat
        // backs facing away from the screen still pick up its colour.
        float facing = (0.6 * max(dot(n, l), 0.0) + 0.4) * max(dot(u.lightNormal[i].xyz, -l), 0.0);
        float3 col = light.sample(s, float2((float(i) + 0.5) / 8.0, 0.5), level(3.0)).rgb;
        c += in.albedo * col * facing * u.gain / (1.0 + d * d * u.falloff) / 8.0;
    }
    return float4(c, 1.0);
}

struct ScreenOut {
    float4 position [[position]];
    float2 uv;
};

// 5 floats per vertex: position, uv.
vertex ScreenOut screenVertex(uint vid [[vertex_id]], const device float *v [[buffer(0)]],
                              constant CinemaUniforms &u [[buffer(1)]]) {
    uint b = vid * 5;
    ScreenOut o;
    o.position = u.viewProj * float4(v[b], v[b + 1], v[b + 2], 1.0);
    o.uv = float2(v[b + 3], v[b + 4]);
    return o;
}

fragment float4 screenFragment(ScreenOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return float4(tex.sample(s, in.uv).rgb, 1.0);
}

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    QuadOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

// Box-filters the screen into the small light texture (64×32) so the glow doesn't shimmer.
fragment float4 downsampleFragment(QuadOut in [[stage_in]], texture2d<float> src [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 step = float2(1.0 / 64.0, 1.0 / 32.0) / 4.0;
    float3 c = float3(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            c += src.sample(s, in.uv + (float2(x, y) - 1.5) * step).rgb;
        }
    }
    return float4(c / 16.0, 1.0);
}
"""
