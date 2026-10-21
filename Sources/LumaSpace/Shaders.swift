// Compiled at runtime with MTLDevice.makeLibrary(source:) — the offline metal compiler ships only with Xcode.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct PanelUniforms {
    float4x4 mvp;
    float aspect;
    float selected;
    float dim;
    float pad;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut panelVertex(uint vid [[vertex_id]], constant PanelUniforms &u [[buffer(0)]]) {
    const float2 corners[4] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5) };
    float2 c = corners[vid];
    VOut o;
    o.position = u.mvp * float4(c, 0.0, 1.0);
    o.uv = float2(c.x + 0.5, 0.5 - c.y);
    return o;
}

fragment float4 panelFragment(VOut in [[stage_in]], constant PanelUniforms &u [[buffer(0)]],
                              texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    // Rounded-rectangle signed distance in panel units (height = 1).
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float2 halfSize = float2(u.aspect, 1.0) * 0.5;
    float r = 0.025;
    float2 q = abs(p) - halfSize + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float aa = fwidth(d);
    float alpha = 1.0 - smoothstep(-aa, aa, d);
    float4 color = tex.sample(s, in.uv);
    color.rgb *= (1.0 - u.dim);
    if (u.selected > 0.5 && d > -0.012) {
        color = float4(0.35, 0.65, 1.0, 1.0);
    }
    return float4(color.rgb, color.a * alpha);
}
"""
