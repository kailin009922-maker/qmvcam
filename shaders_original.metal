#include <metal_stdlib>
using namespace metal;

struct LightParams {
    float3 lightDir;
    float  intensity;
    float3 lightColor;
    float  featherRadius;
    float4 faceRect;
    uint   blendMode;
    uint   regionMask;
    float4 regionYBounds;
    float2 noseXRange;
    uint   width;
    uint   height;
};

// 6 种混合模式
static float3 applyBlend(float3 src, float3 light, float localIntensity, uint mode) {
    float3 result;
    switch (mode) {
        case 0: // SoftLight
            result = select(src * (light + 0.5), src + (1.0 - src) * (light - 0.5), light >= 0.5);
            break;
        case 1: // Overlay
            result = select(2.0 * src * light, 1.0 - 2.0 * (1.0 - src) * (1.0 - light), src >= 0.5);
            break;
        case 2: // Screen
            result = 1.0 - (1.0 - src) * (1.0 - light);
            break;
        case 3: // LinearDodge
            result = src + light;
            break;
        case 4: // HardLight
            result = select(2.0 * src * light, 1.0 - 2.0 * (1.0 - src) * (1.0 - light), light >= 0.5);
            break;
        case 5: // ColorDodge
            result = min(float3(1.0), src / max(float3(0.001), 1.0 - light));
            break;
        default:
            result = src;
            break;
    }
    return clamp(src + (result - src) * localIntensity, 0.0, 1.0);
}

kernel void faceLighting(
    texture2d<float, access::read_write> frame [[texture(0)]],
    texture2d<float, access::sample> normalMap [[texture(1)]],
    constant LightParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    // 1. 边界检查
    if (gid.x >= params.width || gid.y >= params.height) return;

    // 2. 屏幕坐标 → 人脸 UV
    float fx = float(gid.x);
    float fy = float(gid.y);
    float faceX = params.faceRect.x;
    float faceY = params.faceRect.y;
    float faceW = params.faceRect.z;
    float faceH = params.faceRect.w;

    // 加上羽化扩展区域
    float expandX = faceW * params.featherRadius * 0.5;
    float expandY = faceH * params.featherRadius * 0.5;
    float extFaceX = faceX - expandX;
    float extFaceY = faceY - expandY;
    float extFaceW = faceW + expandX * 2.0;
    float extFaceH = faceH + expandY * 2.0;

    // 快速剔除：不在扩展人脸区域内
    if (fx < extFaceX || fx >= extFaceX + extFaceW ||
        fy < extFaceY || fy >= extFaceY + extFaceH) return;

    // 归一化到人脸 UV 空间 (0-1)，以原始 faceRect 为基准
    float u = (fx - faceX) / max(1.0, faceW);
    float v = (fy - faceY) / max(1.0, faceH);

    // 3. 区域掩码检查
    uint regionMask = params.regionMask;
    if (regionMask != 0xF && regionMask != 0) {
        float yNorm = v;
        bool inRegion = false;
        if ((regionMask & 1u) != 0 && yNorm >= params.regionYBounds.x && yNorm < params.regionYBounds.y)
            inRegion = true;
        if ((regionMask & 2u) != 0 && yNorm >= params.regionYBounds.y && yNorm < params.regionYBounds.z)
            inRegion = true;
        if ((regionMask & 4u) != 0 && yNorm >= params.regionYBounds.z && yNorm <= params.regionYBounds.w)
            inRegion = true;
        if ((regionMask & 8u) != 0 && yNorm >= params.regionYBounds.y && yNorm < params.regionYBounds.z
            && u >= params.noseXRange.x && u <= params.noseXRange.y)
            inRegion = true;
        if (!inRegion) return;
    }

    // 4. 椭圆距离
    float ellipseCX = faceX + faceW * 0.5;
    float ellipseCY = faceY + faceH * 0.5;
    float ellipseRX = faceW * 0.5 + expandX;
    float ellipseRY = faceH * 0.5 + expandY;
    float ndx = (fx - ellipseCX) / max(1.0, ellipseRX);
    float ndy = (fy - ellipseCY) / max(1.0, ellipseRY);
    float dist2 = ndx * ndx + ndy * ndy;
    if (dist2 >= 1.0) return;

    // 5. 采样法线贴图
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float sampleU = clamp(u, 0.05, 0.95);
    float sampleV = clamp(v, 0.05, 0.95);
    float4 normalSample = normalMap.sample(linearSampler, float2(sampleU, sampleV));
    float3 N = normalize(normalSample.xyz * 2.0 - 1.0);

    // 法线柔化 30%（版本3）
    float3 flatN = float3(0.0, 0.0, 1.0);
    N = normalize(mix(flatN, N, 0.3));

    // 6. Half-Lambert 漫反射（版本3参数）
    float3 L = normalize(params.lightDir);
    float NdotL = dot(N, L);
    float halfLambert = NdotL * 0.5 + 0.5;
    float diffuse = halfLambert * halfLambert;
    diffuse = 0.20 + 0.80 * diffuse;

    // 7. SSS 近似（版本3：极轻微 0.05）
    float sssZone = smoothstep(0.25, 0.50, halfLambert) * (1.0 - smoothstep(0.50, 0.75, halfLambert));
    float3 sssColor = float3(1.0, 0.4, 0.25) * sssZone * 0.05;

    // 8. 平滑边缘羽化（消除边界圆圈伪影）
    // (1-dist2)^2 在边界处自然衰减到 0，无阶梯跳变
    float feather = (1.0 - dist2) * (1.0 - dist2);

    // ★ 额头点光源（替代 dirGradient）
    float2 lightUV = float2(0.5, 0.28);
    float dLight = distance(float2(u, v), lightUV);
    float spot = exp(-dLight * dLight / (2.0 * 0.40 * 0.40));

    // 9. 综合光照强度
    float3 lightContrib = params.lightColor * diffuse + sssColor;
    float localIntensity = clamp(params.intensity * feather * spot, 0.0, 1.0);

    if (localIntensity < 0.005) return;

    // 10. 读取原始像素 (BGRA → RGBA in Metal)
    float4 pixel = frame.read(gid);
    float3 src = pixel.rgb;

    // 11. 混合模式
    float3 blended = applyBlend(src, lightContrib, localIntensity, params.blendMode);

    // 12. 写回
    frame.write(float4(blended, pixel.a), gid);
}

// ================== 眼神光 Kernel ==================

struct EyeLightParams {
    float4 faceRect;
    float3 lightDir;
    float  eyeSpecularIntensity;
    float  eyeSpecularSize;
    float  _padding1;
    float2 eyeLeftCenter;
    float2 eyeRightCenter;
    uint   width;
    uint   height;
};

kernel void eyeCatchlight(
    texture2d<float, access::read_write> frame [[texture(0)]],
    texture2d<float, access::sample> normalMap [[texture(1)]],
    constant EyeLightParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= params.width || gid.y >= params.height) return;

    float u = (float(gid.x) - params.faceRect.x) / params.faceRect.z;
    float v = (float(gid.y) - params.faceRect.y) / params.faceRect.w;

    float dL = distance(float2(u, v), params.eyeLeftCenter);
    float dR = distance(float2(u, v), params.eyeRightCenter);
    float minD = min(dL, dR);
    if (minD > params.eyeSpecularSize * 2.0) return;  // 保持合理剔除但兼容新的小半径

    float radius = params.eyeSpecularSize;
    float maskL = 1.0 - smoothstep(radius * 0.5, radius * 1.2, dL);  // 内核更小、边缘更柔和
    float maskR = 1.0 - smoothstep(radius * 0.5, radius * 1.2, dR);
    float eyeMask = max(maskL, maskR);
    if (eyeMask < 0.001) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float su = clamp(u, 0.05f, 0.95f);
    float sv = clamp(v, 0.05f, 0.95f);
    float4 nSample = normalMap.sample(s, float2(su, sv));
    float3 N = normalize(nSample.xyz * 2.0 - 1.0);
    N = normalize(mix(float3(0, 0, 1), N, 0.3));

    float3 L = params.lightDir;
    float3 V = float3(0, 0, 1);
    float3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float specular = pow(NdotH, 48.0);

    float4 src = frame.read(gid);
    float specI = specular * params.eyeSpecularIntensity * eyeMask;
    float3 result = min(src.rgb + float3(specI), float3(1.0));  // Additive + clamp，更自然

    frame.write(float4(result, src.a), gid);
}
