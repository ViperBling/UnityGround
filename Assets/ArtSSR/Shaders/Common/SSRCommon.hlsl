#pragma once

#define BINARY_STEP_COUNT 32

#define HIZ_START_LEVEL 0
#define HIZ_MAX_LEVEL 11
#define HIZ_STOP_LEVEL 0

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness

TEXTURE2D_X(_SSRCameraBackFaceDepthTexture);
TEXTURE2D_X(_SSRTempSceneColorTexture);

SAMPLER(sampler_BlitTexture);
SAMPLER(sampler_point_clamp);

TEXTURE2D_ARRAY(_DepthPyramid);
SAMPLER(sampler_DepthPyramid);
float2 _BlueNoiseTextures_TexelSize;
Buffer<uint2> _DepthPyramidResolutions;

CBUFFER_START(UnityPerMaterial)
    int _Frame;
    float3 _WorldSpaceViewDir;
    half _ThicknessScale;
    half _EdgeFade;
    float _StepStride;
    float _MaxSteps;
    float _MinSmoothness;
    half _FadeSmoothness;
    half2 _ScreenResolution;
    half2 _PaddedResolution;
    half2 _PaddedScale;
    half2 _CrossEps;
CBUFFER_END

#ifndef kMaterialFlagSpecularSetup
    #define kMaterialFlagSpecularSetup 8 // Lit material use specular setup instead of metallic setup
#endif

#ifndef kDielectricSpec
    #define kDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
#endif

uint UnpackMaterialFlags(float packedMaterialFlags)
{
    return uint((packedMaterialFlags * 255.0h) + 0.5h);
}

#ifdef _GBUFFER_NORMALS_OCT
half3 UnpackNormal(half3 pn)
{
    half2 remappedOctNormalWS = half2(Unpack888ToFloat2(pn));           // values between [ 0, +1]
    half2 octNormalWS = remappedOctNormalWS.xy * half(2.0) - half(1.0); // values between [-1, +1]
    return half3(UnpackNormalOctQuadEncode(octNormalWS));               // values between [-1, +1]
}
#else
half3 UnpackNormal(half3 pn)
{
    return pn;
}                            // values between [-1, +1]
#endif

float3 GetWorldPosition(float2 screenUV, float rawDepth)
{
    float4 positionNDC = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
    #ifdef UNITY_UV_STARTS_AT_TOP
        positionNDC.y *= -1;
    #endif
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    // 后面会直接用到positionVS，所以要先除以w
    positionVS *= rcp(positionVS.w);
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);

    return positionWS.xyz;
}

inline void HitDataFromGBuffer(float2 texCoord, inout half3 albedo, inout half3 specular, inout half occlusion, inout half3 normal, inout half smoothness)
{
    half4 gBuffer0 = SAMPLE_TEXTURE2D(_GBuffer0, sampler_point_clamp, texCoord);
    half4 gBuffer1 = SAMPLE_TEXTURE2D(_GBuffer1, sampler_point_clamp, texCoord);
    half4 gBuffer2 = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, texCoord);

    albedo = gBuffer0.rgb;
    specular = (UnpackMaterialFlags(gBuffer0.a) == kMaterialFlagSpecularSetup) ? gBuffer1.rgb : lerp(kDielectricSpec.rgb, max(albedo.rgb, kDielectricSpec.rgb), gBuffer1.r); // Specular & Metallic setup conversion
    occlusion = gBuffer1.a;
    normal = UnpackNormal(gBuffer2.xyz);
    smoothness = gBuffer2.w;
}

inline float ScreenEdgeMask(float2 screenUV)
{
    // float yDiff = 1 - abs(screenUV.y);
    // float xDiff = 1 - abs(screenUV.x);
    //
    // UNITY_FLATTEN
    // if (yDiff < 0 || xDiff < 0)
    // {
    //     return 0;
    // }
    //
    // float t1 = smoothstep(0, 0.2, yDiff);
    // float t2 = smoothstep(0, 0.1, xDiff);
    //
    // return saturate(t1 * t2);
    UNITY_BRANCH
    if (_EdgeFade == 0.0)
    {
        return 1.0;
    }
    else
    {
        half fadeRcpLength = rcp(_EdgeFade);
        float2 coordCS = screenUV * 2.0 - 1.0;
        float2 t = Remap10(abs(coordCS.xy), fadeRcpLength, fadeRcpLength);
        return Smoothstep01(t.x) * Smoothstep01(t.y);
    }
}

inline float Dither8x8(float2 screenUV, float c0)
{
    const float dither[64] = 
    {
        0, 32, 8, 40, 2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37,
        63, 31, 55, 23, 61, 29, 53, 21
    };

    c0 *= 2;
    float2 uv = screenUV.xy * _ScreenParams.xy;

    uint index = (uint(uv.x) % 8) * 8 + uint(uv.y) % 8;

    float limit = float(dither[index] + 1) / 64.0;
    return saturate(c0 - limit);
}

inline float IGN(uint pixelX, uint pixelY, uint frame)
{
    frame = frame % 64; // need to periodically reset frame to avoid numerical issues
    float x = float(pixelX) + 5.588238f * float(frame);
    float y = float(pixelY) + 5.588238f * float(frame);
    return fmod(52.9829189f * fmod(0.06711056f * float(x) + 0.00583715f * float(y), 1.0f), 1.0f);
}

inline float RGB2Lum(float3 rgb)
{
    return (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b);
}

inline uint NextPowerOfTwo(uint value)
{
    uint res = 2 << firstbithigh(value - 1);
    return res;
}

inline bool FloatEqApprox(float a, float b)
{
    return abs(a - b) < 0.00001f;
}

// HiZ Tracing
inline uint2 GetLevelResolution(uint index)
{
    uint2 res = _PaddedResolution;
    res.x = res.x >> index;
    res.y = res.y >> index;
    return res;
}

inline float2 ScaledUV(float2 uv, uint index)
{
    float2 scaledScreen = GetLevelResolution(index);
    float realScale = scaledScreen.xy / _PaddedResolution;
    uv *= realScale;
    return uv;
}

inline float SampleDepth(float2 uv, uint index)
{
    uv = ScaledUV(uv, index);
    return SAMPLE_TEXTURE2D_ARRAY(_DepthPyramid, sampler_DepthPyramid, uv, index);
}

inline float2 GetCell(float2 raySS, float2 cellCount)
{
    return floor(raySS.xy * cellCount);
}

inline float2 GetCellCount(float level)
{
    float2 res = GetLevelResolution(level);
    return res;
}

inline bool CrossedCellBoundary(float2 cellID1, float2 cellID2)
{
    return !FloatEqApprox(cellID1.x, cellID2.x) || !FloatEqApprox(cellID1.y, cellID2.y);
}

inline float MiniDepthPlane(float2 ray, float level)
{
    return SampleDepth(ray, level);
}

inline float3 IntersectDepthPlane(float3 origin, float3 dir, float depth)
{
    return origin + dir * depth;
}

inline float3 IntersectCellBoundary(float3 origin, float3 dir, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset)
{
    float2 cellSize = 1.0 / cellCount;
    float2 planes = cellIndex / cellCount + cellSize * crossStep;
    float2 solutions = (planes - origin) / dir.xy;
    float3 intersectionPos = origin + dir * min(solutions.x, solutions.y);

    intersectionPos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);

    return intersectionPos;
}

inline float3 HizTrace(float thickness, float3 positionTS, float3 reflectDirTS, float maxIterations, out float hit, out float iterations, out bool isSky)
{
    const int rootLevel = HIZ_MAX_LEVEL;
    const int endLevel = HIZ_STOP_LEVEL;
    const int startLevel = HIZ_START_LEVEL;
    int level = HIZ_START_LEVEL;

    iterations = 0;
    isSky = false;
    hit = 0;

    UNITY_BRANCH
    if (reflectDirTS.z <= 0) return float3(0, 0, 0);

    float3 depth = reflectDirTS.xyz / reflectDirTS.z;

    float2 crossStep = float2(depth.x >= 0.0f ? 1.0f : - 1.0f, depth.y >= 0.0f ? 1.0f : - 1.0f);
    float2 crossOffset = float2(crossStep.xy * _CrossEps);
    crossStep.xy = saturate(crossStep.xy);

    // Set current ray to original screen coordinate and depth
    float3 rayOrigin = positionTS.xyz;

    float2 rayCell = GetCell(rayOrigin.xy, GetCellCount(level));
    rayOrigin = IntersectCellBoundary(rayOrigin, depth, rayCell.xy, GetCellCount(level), crossStep.xy, crossOffset.xy);

    UNITY_LOOP
    while (level >= endLevel && iterations < maxIterations && rayOrigin.x >= 0 && rayOrigin.x < 1 && rayOrigin.y >= 0 && rayOrigin.y < 1 && rayOrigin.z > 0)
    {
        isSky = false;

        const float2 cellCount = GetCellCount(level);
        const float2 oldCellIdx = GetCell(rayOrigin.xy, cellCount);

        // Get the minimum depth plane of the current ray
        float minZ = MiniDepthPlane(rayOrigin.xy, level);

        float3 tmpRay = rayOrigin;

        float minMinusRay = minZ - rayOrigin.z;

        tmpRay = minMinusRay > 0 ? IntersectDepthPlane(tmpRay, depth, minMinusRay) : tmpRay;

        const float2 newCellIdx = GetCell(tmpRay.xy, cellCount);

        UNITY_BRANCH
        if (CrossedCellBoundary(oldCellIdx, newCellIdx))
        {
            tmpRay = IntersectCellBoundary(rayOrigin, depth, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy);
            level = min(rootLevel, level + 2.0f);
        }
        else if (level == startLevel)
        {
            float minZOffset = (minZ + (1 - positionTS.z) * thickness);
            isSky = minZ == 1;
            
            UNITY_BRANCH
            if (isSky) break;

            UNITY_FLATTEN
            if (tmpRay.z > minZOffset)
            {
                tmpRay = IntersectCellBoundary(rayOrigin, depth, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy);
                level = HIZ_START_LEVEL + 1;
            }
        }

        level--;
        rayOrigin.xyz = tmpRay.xyz;
        ++iterations;
    }
    hit = level < endLevel ? 1 : 0;
    hit = iterations > 0 ? hit : 0;

    return rayOrigin;
}

