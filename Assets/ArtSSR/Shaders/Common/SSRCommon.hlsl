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
#include "Assets/CommonResource/Shaders/Common/Sampling.hlsl"

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness

TEXTURE2D_X(_SSRCameraBackFaceDepthTexture);
TEXTURE2D_X(_SSRSceneColorTexture);
TEXTURE2D_X(_BlueNoiseTexture);

SAMPLER(sampler_BlueNoiseTexture);
SAMPLER(sampler_BlitTexture);
SAMPLER(sampler_point_clamp);

TEXTURE2D_ARRAY(_DepthPyramid);
SAMPLER(sampler_DepthPyramid);

CBUFFER_START(UnityPerMaterial)
    int         _Frame;
    float3      _WorldSpaceViewDir;
    float       _ThicknessScale;
    float       _EdgeFade;
    float       _StepStride;
    float       _MaxSteps;
    float       _MinSmoothness;
    float       _FadeSmoothness;
    float2      _ScreenResolution;
    int         _ReflectSky;
    int         _RandomSeed;
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

float GenerateRandomFloat(float2 screenUV)
{
    float time = unity_DeltaTime.y * _Time.y + _RandomSeed++;
    return GenerateHashedRandomFloat(uint3(screenUV * _ScreenResolution.xy, time));
}

float DistanceSquared(float2 a, float2 b)
{
    return dot(a - b, a - b);
}

inline float SampleDepth(float2 uv)
{
    return SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
}

inline float3 TangentToWorld(float3 vec, float3 tangentZ)
{
    float3 upVector = abs(tangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangentX = normalize(cross(upVector, tangentZ));
    float3 tangentY = cross(tangentZ, tangentX);
    float3x3 tangentToWorld = float3x3(tangentX, tangentY, tangentZ);

    float3 T2W = mul(vec, tangentToWorld);
    return T2W;
}

inline float3 GetReflectDirWS(float2 screenUV, float3 normalWS, float3 viewDirWS, float smoothness, inout bool valid)
{
    // float3 normalVS = normalize(mul(GetWorldToViewMatrix(), normalWS));
    float2 randomUV = float2(GenerateRandomFloat(screenUV), GenerateRandomFloat(screenUV));
    float3 reflectDirWS = ImportanceSampleGGX(randomUV, normalWS, viewDirWS, smoothness, valid);

    // float2 hash = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, screenUV).rg;
    // float3 reflectDirWS = TangentToWorld(ImportanceSampleGGX(hash, smoothness), normalVS);
    // float3 reflectDirWS = reflect(viewDirWS, normalWS);

    return reflectDirWS;
}

inline float3 GetNormalWS(float2 uv, inout float smoothness)
{
    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, uv);
    smoothness = normalGBuffer.a;
    return UnpackNormal(normalGBuffer.xyz);
}

inline float4 ReconstructPositionWS(float2 screenUV, float rawDepth, inout float4 positionNDC, inout float4 positionVS)
{
    positionNDC = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
    // 等价
    positionNDC.y *= _ProjectionParams.x;
    // #ifdef UNITY_UV_STARTS_AT_TOP
    //     positionNDC.y *= -1;
    // #endif
    positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    // 后面会直接用到positionVS，所以要先除以w
    positionVS *= rcp(positionVS.w);
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);

    return positionWS;
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

// =============== HiZ Tracing Start =============== //
inline float2 GetScreenResolution()
{
    return _ScreenResolution;
}

inline uint2 GetLevelResolution(uint index)
{
    uint2 res = GetScreenResolution();
    res.x = res.x >> index;
    res.y = res.y >> index;
    return res;
}

inline float2 ScaledUV(float2 uv, uint index)
{
    float2 scaledScreen = GetLevelResolution(index);
    float realScale = scaledScreen.xy / GetScreenResolution();
    uv *= realScale;
    return uv;
}

inline float SampleDepth(float2 uv, uint index)
{
    uv = ScaledUV(uv, index);
    return SAMPLE_TEXTURE2D_ARRAY(_DepthPyramid, sampler_DepthPyramid, uv, index);
}

inline float2 GetCrossEps()
{
    return 1.0 / GetScreenResolution() / 512.0;
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
    return (int)cellID1.x != (int)cellID2.x || (int)cellID1.y != (int)cellID2.y;
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

    // crossOffset.xy *= 16;
    intersectionPos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);

    return intersectionPos;
}

inline float3 HizTrace(float thickness, float3 positionSS, float3 reflectDirSS, float maxIterations, out float hit, out float iterations, out bool isSky)
{
    const int maxLevel = HIZ_MAX_LEVEL;
    const int stopLevel = HIZ_STOP_LEVEL;
    const int startLevel = HIZ_START_LEVEL;
    int level = HIZ_START_LEVEL;

    iterations = 0;
    isSky = false;
    hit = 0;

    // TS下反射向量的z为负值时，说明反射光线朝着屏幕外部
    UNITY_BRANCH
    if (reflectDirSS.z <= 0) return float3(0, 0, 0);

    float3 dirTS = reflectDirSS.xyz / reflectDirSS.z;

    float2 crossStep = float2(dirTS.x >= 0.0f ? 1.0f : -1.0f, dirTS.y >= 0.0f ? 1.0f : -1.0f);
    float2 crossOffset = float2(crossStep.xy * GetCrossEps());
    crossStep.xy = saturate(crossStep.xy);

    // 确定光线的起始位置
    float3 rayOrigin = positionSS.xyz;

    // 确定当前位置在哪个Cell，Cell是HiZ每层的最小单元，当在Level0的时候，就是屏幕上的像素
    float2 rayCell = GetCell(rayOrigin.xy, GetCellCount(level));
    rayOrigin = IntersectCellBoundary(rayOrigin, dirTS, rayCell.xy, GetCellCount(level), crossStep.xy, crossOffset.xy);

    UNITY_LOOP
    while (level >= stopLevel && iterations < maxIterations 
        //    && rayOrigin.x >= 0 && rayOrigin.x < 1 
        //    && rayOrigin.y >= 0 && rayOrigin.y < 1 && rayOrigin.z > 0
           )
    {
        isSky = false;

        const float2 cellCount = GetCellCount(level);
        const float2 oldCellIdx = GetCell(rayOrigin.xy, cellCount);

        // Get the minimum depth plane of the current ray
        float minZ = MiniDepthPlane(rayOrigin.xy, level);

        float3 tmpRayPos = rayOrigin;

        // 光线相较检测，小于0说明与物体相较
        float depthDelta = minZ - rayOrigin.z;
        tmpRayPos = depthDelta > 0 ? IntersectDepthPlane(tmpRayPos, dirTS, depthDelta) : tmpRayPos;

        // 计算交点位置的Cell
        const float2 newCellIdx = GetCell(tmpRayPos.xy, cellCount);

        // 检测交点是否在离开当前Cell
        UNITY_BRANCH
        if (CrossedCellBoundary(oldCellIdx, newCellIdx))
        {
            // 交点不在当前的Cell，计算交点位置，然后进入下一层
            tmpRayPos = IntersectCellBoundary(rayOrigin, dirTS, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy);
            level = min(maxLevel, level + 1.0f);
        }
        else if (level == startLevel)
        {
            float minZOffset = minZ + (1 - positionSS.z) * thickness;
            // float minZOffset = (minZ + (_ProjectionParams.y * thickness) / LinearEyeDepth(1 - positionSS.z, _ZBufferParams));
            isSky = minZ == 1;
            
            UNITY_BRANCH
            if (tmpRayPos.z > minZOffset || (_ReflectSky == 0 && isSky)) break;

            // UNITY_FLATTEN
            // if (tmpRayPos.z > minZOffset)
            // {
            //     tmpRayPos = IntersectCellBoundary(rayOrigin, dirTS, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy);
            //     level = HIZ_START_LEVEL + 1;
            // }
        }

        level--;
        rayOrigin.xyz = tmpRayPos.xyz;
        ++iterations;
    }
    hit = level < stopLevel ? 1 : 0;
    hit = iterations > 0 ? hit : 0;

    return rayOrigin;
}

// =============== HiZ Tracing End =============== //

