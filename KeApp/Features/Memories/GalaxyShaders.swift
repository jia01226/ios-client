// 11-27：着色器的原文。这台 Mac 的 Xcode 没装 Metal 编译工具（要另下好几个 G），
// 所以不放 .metal 文件让 Xcode 编，App 第一次打开星河时用 makeLibrary(source:) 现编（几十毫秒，只编一次）。

enum GalaxyShaders {
    static let source = """
#include <metal_stdlib>
using namespace metal;

// 11-27 新星河：整片宇宙交给显卡画（她说旧的「比 Vera 的月相卡」）。
// 三种东西：发光的点（星、星尘、云气、背景星）、贴图（星云的画、名字）、拖尾（流星）。全部叠加混合。

struct GalaxyUniforms {
    float4x4 viewProj;
    float4x4 view;
    float4x4 proj;
    float2 viewport;   // 像素
    float time;
    float projScale;   // 世界里 1 个单位、离镜头 1 个单位远时，在屏幕上是多少像素
};

struct GalaxySprite {
    float4 posSize;    // xyz 本地坐标；w 大小（世界单位；背景星是像素）
    float4 color;
    uint4 meta;        // x 属于哪一块（0…9；100+L 是第 L 层背景星）；y 样子；z 闪的相位
};

struct GalaxyQuad {
    float4 center;     // xyz 本地坐标；w 半边长（世界单位）
    float4 tint;
    uint4 meta;        // x 属于哪一块；y 0 面朝镜头 / 1 平躺在盘面 / 2 屏幕上固定像素大小（名字）
    float4 extra;      // 模式 0：x 转角；模式 2：xy 像素偏移、zw 半宽半高（像素）
};

struct GalaxyStreak {
    float4 a;          // 头；w 宽（像素）
    float4 b;          // 尾；w 1 = 已经是屏幕坐标（-1…1）
    float4 ca;
    float4 cb;
};

constant float2 corners[6] = { {-1, -1}, {1, -1}, {-1, 1}, {-1, 1}, {1, -1}, {1, 1} };

struct SpriteOut {
    float4 pos [[position]];
    float2 uv;
    float4 color;
    float kind;
};

vertex SpriteOut galaxySpriteVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                    const device GalaxySprite *sprites [[buffer(0)]],
                                    constant GalaxyUniforms &u [[buffer(1)]],
                                    constant float4x4 *regions [[buffer(2)]],
                                    constant float4x4 *sky [[buffer(3)]]) {
    GalaxySprite s = sprites[iid];
    float2 c = corners[vid];
    SpriteOut o;
    float4 clip;
    float px;
    if (s.meta.x >= 100) {
        clip = sky[s.meta.x - 100] * float4(s.posSize.xyz, 1);
        clip.z = clip.w * 0.9999;
        px = s.posSize.w;
    } else {
        clip = u.viewProj * (regions[s.meta.x] * float4(s.posSize.xyz, 1));
        px = s.posSize.w * u.projScale / max(clip.w, 1.0);
    }
    // 太小的点在屏幕上会一闪一闪地消失：至少一个像素，亮度按缩掉的比例减
    float shrink = 1.0;
    if (px < 1.0) { shrink = max(px, 0.05); px = 1.0; }
    o.pos = clip + float4(c * px / u.viewport * 2.0 * clip.w, 0, 0);
    float tw = 1.0;
    float phase = float(s.meta.z) * 0.001;
    if (s.meta.y == 1) tw = 0.85 + 0.15 * sin(u.time * 1.1 + phase);
    if (s.meta.y == 2) tw = 0.6 + 0.4 * sin(u.time * 3.6 + phase);
    o.color = s.color * tw * shrink;
    if (clip.w <= 0) o.color = float4(0);
    o.uv = c;
    o.kind = float(s.meta.y);
    return o;
}

fragment float4 galaxySpriteFragment(SpriteOut in [[stage_in]]) {
    float d2 = dot(in.uv, in.uv);
    if (d2 > 1.0) discard_fragment();
    float a;
    if (in.kind > 0.5 && in.kind < 2.5) {
        a = exp(-d2 * 14.0) + exp(-d2 * 3.0) * 0.3;     // 记忆星：亮芯 + 一圈光
    } else if (in.kind > 2.5) {
        a = exp(-d2 * 5.0);                              // 背景星
    } else {
        float d = sqrt(d2);
        a = (1.0 - d) * (1.0 - d);                       // 云气、星尘：软软的一团
    }
    return float4(in.color.rgb * in.color.a * a, 0);
}

struct QuadOut {
    float4 pos [[position]];
    float2 uv;
    float4 tint;
};

vertex QuadOut galaxyQuadVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                const device GalaxyQuad *quads [[buffer(0)]],
                                constant GalaxyUniforms &u [[buffer(1)]],
                                constant float4x4 *regions [[buffer(2)]]) {
    GalaxyQuad q = quads[iid];
    float2 c = corners[vid];
    float4x4 m = regions[q.meta.x];
    QuadOut o;
    float4 clip;
    if (q.meta.y == 1) {
        float3 local = q.center.xyz + float3(c.x * q.center.w, 0, -c.y * q.center.w);
        clip = u.viewProj * (m * float4(local, 1));
    } else if (q.meta.y == 0) {
        float4 v = u.view * (m * float4(q.center.xyz, 1));
        float r = q.extra.x;
        float2 k = float2(c.x * cos(r) - c.y * sin(r), c.x * sin(r) + c.y * cos(r));
        v.xy += k * q.center.w;
        clip = u.proj * v;
    } else {
        clip = u.viewProj * (m * float4(q.center.xyz, 1));
        float2 p = q.extra.xy + c * q.extra.zw;
        clip.xy += p / u.viewport * 2.0 * clip.w;
    }
    o.pos = clip;
    o.uv = float2(c.x * 0.5 + 0.5, 0.5 - c.y * 0.5);
    o.tint = clip.w > 0 ? q.tint : float4(0);
    return o;
}

fragment float4 galaxyQuadFragment(QuadOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) {
    float4 t = tex.sample(smp, in.uv);
    return float4(t.rgb * in.tint.rgb * in.tint.a, 0);
}

struct StreakOut {
    float4 pos [[position]];
    float4 color;
    float side;
};

vertex StreakOut galaxyStreakVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                    const device GalaxyStreak *streaks [[buffer(0)]],
                                    constant GalaxyUniforms &u [[buffer(1)]]) {
    GalaxyStreak s = streaks[iid];
    float2 c = corners[vid];
    float t = c.x * 0.5 + 0.5;
    float2 pa, pb;
    bool behind = false;
    if (s.b.w > 0.5) {
        pa = s.a.xy; pb = s.b.xy;
    } else {
        float4 ca = u.viewProj * float4(s.a.xyz, 1), cb = u.viewProj * float4(s.b.xyz, 1);
        behind = ca.w <= 0 || cb.w <= 0;
        pa = ca.xy / max(ca.w, 0.001); pb = cb.xy / max(cb.w, 0.001);
    }
    float2 d = (pb - pa) * u.viewport;
    float len = max(length(d), 0.001);
    float2 n = float2(-d.y, d.x) / len;
    float2 p = mix(pa, pb, t) + n * c.y * s.a.w / u.viewport * 2.0;
    StreakOut o;
    o.pos = float4(p, 0, 1);
    o.color = behind ? float4(0) : mix(s.ca, s.cb, t);
    o.side = c.y;
    return o;
}

fragment float4 galaxyStreakFragment(StreakOut in [[stage_in]]) {
    float a = 1.0 - abs(in.side);
    return float4(in.color.rgb * in.color.a * a * a, 0);
}
"""
}
