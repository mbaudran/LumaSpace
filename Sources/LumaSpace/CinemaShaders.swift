// Compiled at runtime with MTLDevice.makeLibrary(source:), like shaderSource.
// The geometry helpers mirror LumaCore/CinemaAmbience.swift, where they are checked.
let cinemaShaderSource = """
#include <metal_stdlib>
using namespace metal;

// Packed by CinemaRenderer.uniforms(), in this order.
struct CinemaUniforms {
    float4x4 viewProj;
    float4x4 invViewProj;
    float4 eye;          // xyz, w = seconds since cinema started
    float4 screen;       // axis z, radius, half angle, corner radius
    float4 screenY;      // top, height, width, floor y
    float4 strength;     // halo, haze, reflection, dust
    float4 misc;         // bloom, fade, dust pixels per unit at depth 1, unused
    float4 dustMin;
    float4 dustSize;
    float4 lightPos[16];    // w = u
    float4 lightNormal[16]; // w = v
};

constant float hazeSoftening = 0.25;  // hazeSoftening in CinemaAmbience.swift
constant float hazeGain = 0.22;
constant float poolGain = 0.05;
constant float haloGain = 0.8;
constant float dustGain = 5.0;
constant float reflectionGain = 1.3;
constant float bloomGain = 0.7;

constexpr sampler glowSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

// The 16 light colours, worked out once per frame (lightsFragment) into a 16×1 texture.
float3 lightColor(texture2d<float> lights, int i) {
    return lights.read(uint2(i, 0)).rgb;
}

// screenHit() without the bounds check: (u, v, t), t < 0 when the ray can't reach the screen.
float3 screenHitRaw(float3 o, float3 d, constant CinemaUniforms &u) {
    float axisZ = u.screen.x, r = u.screen.y, halfAngle = u.screen.z;
    float ox = o.x, oz = o.z - axisZ;
    float a = d.x * d.x + d.z * d.z, b = ox * d.x + oz * d.z, c = ox * ox + oz * oz - r * r;
    if (a < 1e-6 || c >= 0.0) return float3(0.0, 0.0, -1.0);
    float t = (-b + sqrt(b * b - a * c)) / a;
    float3 p = o + d * t;
    float uu = (atan2(p.x, axisZ - p.z) / halfAngle + 1.0) * 0.5;
    float vv = (u.screenY.x - p.y) / u.screenY.y;
    return float3(uu, vv, t);
}

bool onScreen(float3 h) {
    return h.z > 0.0 && h.x >= 0.0 && h.x <= 1.0 && h.y >= 0.0 && h.y <= 1.0;
}

// hazeIntegral(), plus a lobe so the screen mostly lights the air in front of it.
float3 haze(float3 o, float3 d, float len, constant CinemaUniforms &u, texture2d<float> lights) {
    float3 sum = float3(0.0);
    for (int i = 0; i < 16; i++) {
        float3 L = u.lightPos[i].xyz;
        float3 w = o - L;
        float b = dot(d, w);
        float h = sqrt(max(dot(w, w) - b * b, 0.0) + hazeSoftening);
        float k = (atan((len + b) / h) - atan(b / h)) / h;
        float3 nearest = o + d * clamp(-b, 0.0, len);
        float lobe = 0.25 + 0.75 * max(dot(u.lightNormal[i].xyz, normalize(nearest - L + float3(0.0, 0.0, 1e-4))), 0.0);
        sum += lightColor(lights, i) * k * lobe;
    }
    return sum / 16.0 * hazeGain * u.strength.y;
}

struct Varyings {
    float4 position [[position]];
    float3 world;
    float2 uv;
};

// 6 floats per vertex: position, then two floats each pipeline reads as it likes.
vertex Varyings sceneVertex(uint vid [[vertex_id]], const device float *v [[buffer(0)]],
                            constant CinemaUniforms &u [[buffer(1)]]) {
    uint b = vid * 6;
    Varyings o;
    o.world = float3(v[b], v[b + 1], v[b + 2]);
    o.uv = float2(v[b + 3], v[b + 4]);
    o.position = u.viewProj * float4(o.world, 1.0);
    return o;
}

// Black lacquer: a blurred reflection of the screen, strongest at grazing angles, and a soft pool
// of the screen's light.
fragment float4 floorFragment(Varyings in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                              texture2d<float> glow [[texture(0)]], texture2d<float> lights [[texture(1)]]) {
    float3 eye = u.eye.xyz, p = in.world;
    float3 d = normalize(p - eye);
    float3 r = float3(d.x, -d.y, d.z);
    float3 c = float3(0.0);
    float3 hit = screenHitRaw(p, r, u);
    if (hit.z > 0.0) {
        float soft = 0.004 + hit.z * 0.012;
        float2 edge = min(hit.xy, 1.0 - hit.xy);
        float mask = smoothstep(-soft, soft, edge.x) * smoothstep(-soft, soft, edge.y);
        float lod = clamp(log2(1.0 + hit.z * 2.0), 0.0, 6.0);
        float cosTheta = max(-d.y, 0.0);
        float fresnel = 0.1 + 0.9 * pow(1.0 - cosTheta, 5.0);  // still water / black lacquer
        c += glow.sample(glowSampler, saturate(hit.xy), level(lod)).rgb * mask * fresnel * reflectionGain * u.strength.z;
    }
    // The bottom row of lights is the one near the floor.
    float3 pool = float3(0.0);
    for (int i = 8; i < 16; i++) {
        float3 L = u.lightPos[i].xyz - p;
        float dist = length(L);
        float3 l = L / max(dist, 0.01);
        pool += lightColor(lights, i) * max(l.y, 0.0) * max(dot(u.lightNormal[i].xyz, -l), 0.0) / (1.0 + dist * dist * 0.08);
    }
    c += pool / 8.0 * poolGain * (0.4 + u.strength.z);
    return float4(c, 1.0);
}

// A strip behind the screen; uv is (arc metres from the centre, height). Each point glows with the
// nearest edge of the picture, fading with distance from it.
fragment float4 haloFragment(Varyings in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                             texture2d<float> glow [[texture(0)]]) {
    float w = u.screenY.z, h = u.screenY.y, top = u.screenY.x;
    float2 q = in.uv;
    float2 nearest = float2(clamp(q.x, -w * 0.5, w * 0.5), clamp(q.y, top - h, top));
    float dist = length(q - nearest);
    float2 suv = float2(nearest.x / w + 0.5, (top - nearest.y) / h);
    float3 col = glow.sample(glowSampler, suv, level(5.0)).rgb;
    // Fades out above the floor so it doesn't end in a hard line where it meets it.
    float fall = exp(-dist / 0.6) * (1.0 - smoothstep(1.6, 2.4, dist)) * smoothstep(u.screenY.w, u.screenY.w + 0.7, in.world.y);
    return float4(col * fall * haloGain * u.strength.x, 1.0);
}

// uv runs 0...1 across the picture; the corners are rounded.
fragment float4 screenFragment(Varyings in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                               texture2d<float> tex [[texture(0)]]) {
    float2 size = float2(u.screenY.z, u.screenY.y);
    float r = u.screen.w;
    float2 q = abs((in.uv - 0.5) * size) - (size * 0.5 - r);
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float alpha = clamp(0.5 - sd / max(fwidth(sd), 1e-5), 0.0, 1.0);
    return float4(tex.sample(linearSampler, in.uv).rgb, alpha);
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

// The light in the air along each view ray, up to the floor or the screen. It's smooth, so it's
// drawn at a quarter of the resolution and added in compositeFragment.
fragment float4 hazeFragment(QuadOut in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                             texture2d<float> lights [[texture(0)]]) {
    float4 far = u.invViewProj * float4(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0, 1.0, 1.0);
    float3 eye = u.eye.xyz;
    float3 d = normalize(far.xyz / far.w - eye);
    float len = 40.0;
    if (d.y < -1e-4) len = min(len, (u.screenY.w - eye.y) / d.y);
    float3 hit = screenHitRaw(eye, d, u);
    if (onScreen(hit)) len = min(len, hit.z);
    return float4(haze(eye, d, len, u, lights), 1.0);
}

float dustHash(float i, float k) {
    return fract(sin(i * 12.9898 + k * 78.233) * 43758.5453);
}

struct DustOut {
    float4 position [[position]];
    float size [[point_size]];
    float3 color;
};

// dustMote(): slow wandering drift wrapping around inside the dust box, lit like the haze.
vertex DustOut dustVertex(uint vid [[vertex_id]], constant CinemaUniforms &u [[buffer(0)]],
                          texture2d<float> lights [[texture(0)]]) {
    float i = float(vid), t = u.eye.w;
    float h0 = dustHash(i, 0.0), h1 = dustHash(i, 1.0), h2 = dustHash(i, 2.0);
    float h3 = dustHash(i, 3.0), h4 = dustHash(i, 4.0), h5 = dustHash(i, 5.0);
    float3 drift = float3(0.25 * sin(t * 0.07 * (0.5 + h3) + 6.283 * h4),
                          t * 0.012 * (0.4 + h5),
                          0.25 * sin(t * 0.05 * (0.5 + h4) + 6.283 * h3));
    float3 size = u.dustSize.xyz;
    float3 f = fract(float3(h0, h1, h2) + drift / size);
    float3 p = u.dustMin.xyz + size * f;
    // Fade near the box's faces, where motes wrap around.
    float3 edge = smoothstep(0.0, 0.08, min(f, 1.0 - f));
    float3 light = float3(0.0);
    for (int k = 0; k < 16; k++) {
        float3 L = p - u.lightPos[k].xyz;
        float lobe = max(dot(u.lightNormal[k].xyz, normalize(L)), 0.0);
        light += lightColor(lights, k) * lobe / (1.0 + dot(L, L) * 0.15);
    }
    float twinkle = 0.6 + 0.4 * sin(t * (1.0 + h4 * 2.0) + h0 * 40.0);
    DustOut o;
    o.position = u.viewProj * float4(p, 1.0);
    o.size = clamp(0.012 * u.misc.z / max(o.position.w, 0.1), 1.0, 6.0);
    o.color = light / 16.0 * dustGain * u.strength.w * edge.x * edge.y * edge.z * twinkle;
    return o;
}

fragment float4 dustFragment(DustOut in [[stage_in]], float2 pc [[point_coord]]) {
    float a = saturate(1.0 - length(pc * 2.0 - 1.0));
    return float4(in.color * a * a, 1.0);
}

// The picture shrunk into the glow texture and blended with the previous one (smoothing).
fragment float4 glowFragment(QuadOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                             texture2d<float> prev [[texture(1)]], constant float &blend [[buffer(0)]]) {
    float2 step = float2(1.0 / 256.0, 1.0 / 144.0) / 4.0;
    float3 c = float3(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            c += src.sample(linearSampler, in.uv + (float2(x, y) - 1.5) * step).rgb;
        }
    }
    return float4(mix(prev.sample(linearSampler, in.uv).rgb, c / 16.0, blend), 1.0);
}

// Texel i of the 16×1 light texture: the picture around light i, blurred.
fragment float4 lightsFragment(QuadOut in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                               texture2d<float> glow [[texture(0)]]) {
    int i = min(int(in.position.x), 15);
    return float4(glow.sample(glowSampler, float2(u.lightPos[i].w, u.lightNormal[i].w), level(4.0)).rgb, 1.0);
}

// Keeps a bloom/composite sample inside its own eye's half of the side-by-side frame.
float2 inEye(float2 uv, float2 texel) {
    float lo = uv.x < 0.5 ? 0.0 : 0.5;
    return float2(clamp(uv.x, lo + texel.x * 0.5, lo + 0.5 - texel.x * 0.5), uv.y);
}

// The bright parts of the scene, at a quarter of its size.
fragment float4 bloomExtractFragment(QuadOut in [[stage_in]], texture2d<float> scene [[texture(0)]]) {
    float2 texel = 1.0 / float2(scene.get_width(), scene.get_height());
    float3 c = float3(0.0);
    for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 2; x++) {
            c += scene.sample(linearSampler, inEye(in.uv + (float2(x, y) - 0.5) * texel * 2.0, texel)).rgb;
        }
    }
    c /= 4.0;
    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    return float4(c * smoothstep(0.45, 1.0, luma), 1.0);
}

// One direction of a separable Gaussian blur.
fragment float4 blurFragment(QuadOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                             constant float2 &dir [[buffer(0)]]) {
    float2 texel = 1.0 / float2(src.get_width(), src.get_height());
    const float w[5] = {0.227, 0.194, 0.122, 0.054, 0.016};
    float3 c = src.sample(linearSampler, in.uv).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        float2 o = dir * texel * float(i) * 1.5;
        c += src.sample(linearSampler, inEye(in.uv + o, texel)).rgb * w[i];
        c += src.sample(linearSampler, inEye(in.uv - o, texel)).rgb * w[i];
    }
    return float4(c, 1.0);
}

// Scene plus bloom, a soft shoulder above 0.8 (normal picture values pass unchanged), the fade-in,
// and dither so the dark gradients don't band on the 8-bit display.
fragment float4 compositeFragment(QuadOut in [[stage_in]], texture2d<float> scene [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]], texture2d<float> haze [[texture(2)]],
                                  constant CinemaUniforms &u [[buffer(0)]]) {
    float3 c = scene.read(uint2(in.position.xy)).rgb;
    float2 bt = 1.0 / float2(bloom.get_width(), bloom.get_height());
    c += bloom.sample(linearSampler, inEye(in.uv, bt)).rgb * bloomGain * u.misc.x;
    float2 ht = 1.0 / float2(haze.get_width(), haze.get_height());
    c += haze.sample(linearSampler, inEye(in.uv, ht)).rgb * step(1e-4, u.strength.y);
    float3 over = max(c - 0.8, 0.0);
    c = min(c, 0.8) + 0.2 * (1.0 - exp(-over / 0.2));
    c *= u.misc.y;
    float n = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    return float4(c + (n - 0.5) / 255.0, 1.0);
}

// LUMA_CINEMA=clip: scrolling colour bars, a drifting sun and a white flash every 3 s.
fragment float4 clipFragment(QuadOut in [[stage_in]], constant float &t [[buffer(0)]]) {
    const float3 bars[7] = {float3(0.75), float3(0.75, 0.75, 0.0), float3(0.0, 0.75, 0.75), float3(0.0, 0.75, 0.0),
                            float3(0.75, 0.0, 0.75), float3(0.75, 0.0, 0.0), float3(0.0, 0.0, 0.75)};
    float x = fract(in.uv.x + t * 0.04);
    float3 c = bars[min(int(x * 7.0), 6)] * (0.35 + 0.65 * in.uv.y);
    float2 sun = float2(0.5 + 0.35 * sin(t * 0.4), 0.35 + 0.15 * cos(t * 0.3));
    float2 d = (in.uv - sun) * float2(16.0 / 9.0, 1.0);
    c = mix(c, float3(1.0, 0.85, 0.5), smoothstep(0.09, 0.07, length(d)));
    if (fract(t / 3.0) < 0.06) c = float3(1.0);
    return float4(c, 1.0);
}
"""
