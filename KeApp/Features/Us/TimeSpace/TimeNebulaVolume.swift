import SceneKit

/// Each pixel integrates a three-dimensional density field along a ray.
/// The plane is only the rendering surface; no nebula image is sampled.
enum TimeNebulaVolume {
    static let noise = """
    float spaceHash(float3 p) {
        p = fract(p * 0.3183099 + float3(0.13, 0.27, 0.41));
        p *= 17.0;
        return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
    }
    float spaceNoise(float3 p) {
        float3 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(mix(spaceHash(i), spaceHash(i + float3(1,0,0)), f.x),
                       mix(spaceHash(i + float3(0,1,0)), spaceHash(i + float3(1,1,0)), f.x), f.y),
                   mix(mix(spaceHash(i + float3(0,0,1)), spaceHash(i + float3(1,0,1)), f.x),
                       mix(spaceHash(i + float3(0,1,1)), spaceHash(i + float3(1,1,1)), f.x), f.y), f.z);
    }
    float spaceFbm(float3 p) {
        return spaceNoise(p) * 0.57 + spaceNoise(p * 2.07 + 5.2) * 0.28
             + spaceNoise(p * 4.31 + 11.7) * 0.15;
    }
    """

    static var fragment: String { """
    #pragma arguments
    float u_travel;
    float u_motion;
    float u_aspect;
    #pragma declaration
    \(noise)
    float nebulaDensity(float3 p) {
        float warp = spaceFbm(p * 1.3) - 0.5;
        float frontPath = p.x - 0.50 - 0.30 * sin(p.y * 1.6) - warp * 0.65;
        float frontZ = p.z - 0.85 - 0.22 * sin(p.y * 1.1);
        float front = exp(-frontPath * frontPath * 8.0 - frontZ * frontZ * 5.5);
        float backPath = p.x + 0.05 + 0.42 * sin(p.y * 1.3 + 0.8) + warp * 0.35;
        float back = exp(-backPath * backPath * 4.0 - (p.z + 0.9) * (p.z + 0.9) * 4.0);
        float fiber = spaceFbm(p * float3(18.0, 3.8, 10.0) + warp * 2.0);
        float strands = pow(max(0.0, 1.0 - abs(fiber * 2.0 - 1.0)), 18.0);
        float gaps = smoothstep(0.28, 0.61, spaceFbm(p * 4.0 + 13.0));
        return (front * (0.14 + strands * 2.4) + back * (0.10 + strands * 1.3)) * gaps;
    }
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float2 screen = (uv - 0.5) * float2(u_aspect * 4.0, 4.0);
    float t = scn_frame.time * 0.065 * u_motion;
    float3 origin = float3(screen.x, -screen.y + u_travel * 0.7, 3.0 - u_travel * 0.45);
    float3 ray = normalize(float3(screen.x * 0.055, -screen.y * 0.055, -1.0));
    float transmission = 1.0;
    float3 scattered = float3(0.0);
    for (int step = 0; step < 36; ++step) {
        float3 p = origin + ray * (float(step) + 0.5) * 0.16;
        float3 drift = float3(sin(t * 0.37 + p.z) * 0.065, t * 0.075, t * 0.043);
        float3 q = p + drift;
        float density = nebulaDensity(q) * 0.22;
        float3 towardLight = normalize(float3(-0.6,0.8,0.65));
        float obstruction = nebulaDensity(q + towardLight * 0.24)
                          + nebulaDensity(q + towardLight * 0.53) * 0.5;
        float illumination = exp(-obstruction * 2.5);
        float alpha = 1.0 - exp(-density * 0.16 * 2.7);
        float3 color = mix(float3(0.82,0.805,0.78), float3(1.0,0.99,0.96), illumination);
        color += float3(0.08,0.075,0.06) * max(0.0, density - obstruction) * illumination;
        scattered += transmission * alpha * color;
        transmission *= 1.0 - alpha;
    }
    float3 base = float3(0.985,0.980,0.969);
    _output.color = float4(pow(clamp(base * transmission + scattered, 0.0, 1.0), float3(2.2)), 1.0);
    """ }

    static var silverSurface: String { """
    #pragma declaration
    \(noise)
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float longitude = uv.x * 6.2831853;
    float latitude = uv.y * 3.1415927;
    float3 p = float3(sin(latitude)*cos(longitude), cos(latitude), sin(latitude)*sin(longitude));
    float mineral = spaceFbm(p * 6.0);
    float dust = spaceNoise(p * 95.0);
    float silver = 0.31 + mineral * 0.28 + dust * 0.025;
    _surface.diffuse.rgb = float3(silver * 0.98, silver, silver * 1.035);
    """ }

    static let atmosphere = """
    #pragma transparent
    #pragma body
    float3 n = normalize(_surface.normal);
    float facing = abs(dot(n, normalize(_surface.view)));
    float fresnel = pow(1.0 - facing, 2.8) * smoothstep(0.0, 0.18, facing);
    float light = smoothstep(-0.35, 0.85, dot(n, normalize(float3(-0.65,0.6,0.4))));
    float alpha = fresnel * (0.025 + light * 0.52);
    _output.color = float4(float3(1.0,0.97,0.88) * alpha, alpha);
    """
}
