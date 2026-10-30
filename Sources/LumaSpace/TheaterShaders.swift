// The theater's surfaces. Appended to cinemaShaderSource (it uses CinemaUniforms, lightColor and
// decode from there). Material numbers are TheaterMaterial's raw values; the geometry constants
// mirror TheaterSpec.
let theaterShaderSource = """

constant float finSpacing = 1.8, finStart = -5.2, halfWidth = 5.6, ceilingY = 8.5;
constant float rowSpacing = 1.1, rowRise = 0.4, seatBlockHalf = 3.6;
constant float screenGain = 2.2;
constant float3 warmLED = float3(1.0, 0.72, 0.48);

struct TheaterOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
    float material [[flat]];
    float ao;
};

// 10 floats per vertex: position, normal, uv (metres), material, ao; each instance is offset.
vertex TheaterOut theaterVertex(uint vid [[vertex_id]], uint iid [[instance_id]], const device float *v [[buffer(0)]],
                                constant CinemaUniforms &u [[buffer(1)]], const device float4 *offsets [[buffer(2)]]) {
    uint b = vid * 10;
    TheaterOut o;
    o.world = float3(v[b], v[b + 1], v[b + 2]) + offsets[iid].xyz;
    o.normal = float3(v[b + 3], v[b + 4], v[b + 5]);
    o.uv = float2(v[b + 6], v[b + 7]);
    o.material = v[b + 8];
    o.ao = v[b + 9];
    o.position = u.viewProj * float4(o.world, 1.0);
    return o;
}

// The seats as seen from behind the screen, for their shadows.
vertex float4 theaterShadowVertex(uint vid [[vertex_id]], uint iid [[instance_id]], const device float *v [[buffer(0)]],
                                  constant CinemaUniforms &u [[buffer(1)]], const device float4 *offsets [[buffer(2)]]) {
    uint b = vid * 10;
    return u.shadowViewProj * float4(float3(v[b], v[b + 1], v[b + 2]) + offsets[iid].xyz, 1.0);
}

struct Finish {
    int layer;      // texture layer, or -1 for a plain colour
    float tiling;   // texture repeats per metre
    float3 tint;    // multiplies the texture (or is the colour)
    float rough;    // used when there's no roughness texture
    float spec;     // how much specular highlight
};

Finish finish(int m) {
    switch (m) {
    case 0: return {0, 3.5, float3(1.9, 1.9, 2.2), 0.45, 1.6};               // leather (the scan is darker than real black leather)
    case 1: return {1, 0.7, float3(0.30, 0.30, 0.33), 0.9, 0.1};   // wall fabric, charcoal
    case 2: return {2, 0.9, float3(0.42, 0.42, 0.50), 0.95, 0.03}; // carpet
    case 3: return {1, 0.7, float3(0.07, 0.07, 0.08), 0.95, 0.0};  // ceiling and wall backing
    case 4: return {-1, 1.0, float3(0.003), 0.95, 0.0};            // black velvet masking
    case 5: return {-1, 1.0, float3(0.03), 0.3, 1.0};              // trim
    default: return {-1, 1.0, float3(0.0), 1.0, 0.0};
    }
}

// Normal mapping without tangents: the frame comes from screen-space derivatives.
float3 perturb(float3 n, float3 p, float2 uv, float3 m) {
    float3 dp1 = dfdx(p), dp2 = dfdy(p);
    float2 duv1 = dfdx(uv), duv2 = dfdy(uv);
    float3 dp2perp = cross(dp2, n), dp1perp = cross(n, dp1);
    float3 t = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 b = dp2perp * duv1.y + dp1perp * duv2.y;
    float s = rsqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
    return normalize(float3x3(t * s, b * s, n) * m);
}

// Soft shadows of the seats, from behind the screen. Some light still gets round them: the screen
// is wide.
float seatShadow(float3 p, float3 n, constant CinemaUniforms &u, depth2d<float> map) {
    float4 s = u.shadowViewProj * float4(p + n * 0.04, 1.0);
    if (s.w <= 0.0) return 1.0;
    float3 c = s.xyz / s.w;
    float2 uv = float2(c.x * 0.5 + 0.5, 0.5 - c.y * 0.5);
    if (any(uv < 0.0) || any(uv > 1.0)) return 1.0;
    constexpr sampler cmp(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);
    const float2 taps[8] = {float2(-0.33, 0.94), float2(0.80, 0.52), float2(-0.95, -0.10), float2(0.12, -0.72),
                            float2(0.55, -0.20), float2(-0.42, 0.25), float2(-0.62, -0.68), float2(0.48, -0.88)};
    float lit = 0.0, radius = 4.0 / float(map.get_width());
    for (int i = 0; i < 8; i++) lit += map.sample_compare(cmp, uv + taps[i] * radius, c.z - 0.0008);
    return mix(0.2, 1.0, lit / 8.0);
}

// Darkening the textures can't show: under the rows of seats and where risers meet.
float roomOcclusion(float3 p, float3 n, int m) {
    float ao = 1.0;
    if (m != 2) return ao;
    float r = round(p.y / rowRise);
    if (n.y > 0.7) {
        // The row of seats on this floor: a long box at its centre line.
        float2 q = abs(float2(p.x, p.z - (r * rowSpacing + 0.02))) - float2(seatBlockHalf + 0.08, 0.38);
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
        if (r >= 0.0 && r <= 7.0) ao *= mix(0.25, 1.0, smoothstep(-0.02, 0.4, d));
        ao *= mix(0.45, 1.0, smoothstep(0.0, 0.45, (r + 0.5) * rowSpacing - p.z));
    } else if (n.z < -0.7) {
        ao *= mix(0.5, 1.0, smoothstep(0.0, 0.3, p.y - (ceil(p.y / rowRise) - 1.0) * rowRise));
    }
    return ao;
}

fragment float4 theaterFragment(TheaterOut in [[stage_in]], constant CinemaUniforms &u [[buffer(0)]],
                                constant float &textured [[buffer(1)]],
                                texture2d_array<float> albedoMaps [[texture(0)]], texture2d_array<float> normalMaps [[texture(1)]],
                                texture2d_array<float> roughMaps [[texture(2)]], depth2d<float> shadowMap [[texture(3)]],
                                texture2d<float> lights [[texture(4)]]) {
    int m = int(in.material + 0.5);
    float house = u.room1.w;
    float3 p = in.world;
    // Emissive parts: LED strips, step lights (never fully off) and the projector port.
    if (m == 6) return float4(warmLED * (0.05 + 4.0 * house), 1.0);
    if (m == 7) return float4(float3(1.0, 0.75, 0.45) * (0.5 + 1.5 * house), 1.0);
    float3 avg = lightColor(lights, 16);  // the picture's average colour
    if (m == 8) return float4(avg * 6.0 * u.beam.w + 0.01, 1.0);
    Finish f = finish(m);
    float3 n = normalize(in.normal);
    float3 albedo = f.tint;
    float rough = f.rough;
    if (f.layer >= 0 && textured > 0.5) {
        constexpr sampler s(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
        float2 uv = in.uv * f.tiling;
        float3 t = albedoMaps.sample(s, uv, f.layer).rgb;  // sRGB texture: already linear here
        // The leather scan is mottled brown; keep a little of its variation on a near-black.
        albedo = m == 0 ? float3(0.026, 0.025, 0.028) * clamp(dot(t, float3(0.33)) / 0.006, 0.7, 1.3) : albedo * t;
        float3 mn = normalMaps.sample(s, uv, f.layer).rgb * 2.0 - 1.0;
        n = perturb(n, p, uv, mn);
        rough = roughMaps.sample(s, uv, f.layer).r * (m == 0 ? 0.75 : 1.0);  // leather: a little sheen
    } else if (f.layer >= 0) {
        albedo *= m == 0 ? 0.03 : 0.25;
    }

    // The screen's light: 8 columns of it (each pair of lights merged), each like a small area light.
    float3 V = normalize(u.eye.xyz - p);
    float area = u.screenY.z * u.screenY.y / 8.0;
    float shininess = 2.0 / max(pow(rough, 4.0), 1e-3) - 2.0;
    float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(n, V), 0.0), 5.0);
    float3 diffuse = float3(0.0), specular = float3(0.0);
    for (int i = 0; i < 8; i++) {
        float3 L = (u.lightPos[i].xyz + u.lightPos[i + 8].xyz) * 0.5 - p;
        float d2 = dot(L, L);
        float3 l = L * rsqrt(d2);
        float ndl = max(dot(n, l), 0.0);
        float3 col = (lightColor(lights, i) + lightColor(lights, i + 8)) * 0.5;
        float3 e = col * max(dot(u.lightNormal[i].xyz, -l), 0.0) * area / (d2 + area) * ndl;
        diffuse += e;
        specular += e * pow(max(dot(n, normalize(l + V)), 0.0), shininess);
    }
    float3 c = (albedo / M_PI_F * diffuse + specular * f.spec * fresnel * (shininess + 8.0) / (8.0 * M_PI_F)) * screenGain;
    c *= seatShadow(p, normalize(in.normal), u, shadowMap);

    // Light bounced around the hall: a faint glow in the film's average colour, weaker at the back.
    c += albedo * avg * 0.06 * screenGain / (1.0 + max(p.z - u.screen.x + u.screen.y, 0.0) * 0.08);

    // House lights: a warm fill with a soft sheen from above, and the LED strips washing the walls
    // between the fins.
    float3 house3 = albedo * warmLED * house;
    c += house3 * (0.06 + 0.9 * house) * (0.6 + 0.4 * n.y);  // full house lights are much brighter than dimmed ones
    float3 top = normalize(float3(0.0, 1.0, 0.35));
    c += warmLED * house * 0.04 * f.spec * fresnel * pow(max(dot(n, normalize(top + V)), 0.0), shininess) * (shininess + 8.0) / (8.0 * M_PI_F);
    float wall = halfWidth - abs(p.x);
    if (wall < 1.2) {
        float k = (p.z - finStart) / finSpacing;
        float gap = abs(k - round(k)) * finSpacing;
        float band = smoothstep(0.8, 1.8, p.y) * smoothstep(ceilingY - 0.6, ceilingY - 2.0, p.y);
        c += house3 * 6.0 * exp(-gap * gap / 0.12) * exp(-wall * 2.5) * band;
    }
    return float4(c * in.ao * roomOcclusion(p, n, m), 1.0);
}
"""
