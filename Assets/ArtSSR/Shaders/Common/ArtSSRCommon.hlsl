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
#include "Assets/CommonResource/Shaders/Common/BSDFLibrary.hlsl"
#include "Assets/CommonResource/Shaders/Common/Random.hlsl"
#include "Assets/CommonResource/Shaders/Common/FilterLibrary.hlsl"

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness

TEXTURE2D_X(_SSRCameraBackFaceDepthTexture);
TEXTURE2D_X(_SSRSceneColorTexture);
TEXTURE2D_X(_BlueNoiseTexture);
TEXTURE2D_X(_BRDFLUT);
TEXTURE2D_X(_SSRReflectionColorTexture);
TEXTURE2D_X(_SSRTemporalHistoryTexture);
TEXTURE2D_X(_MotionVectorTexture);
float4 _MotionVectorTexture_TexelSize;

SAMPLER(sampler_BlueNoiseTexture);
SAMPLER(sampler_BRDFLUT);
SAMPLER(sampler_SSRSceneColorTexture);
SAMPLER(sampler_BlitTexture);
SAMPLER(sampler_point_clamp);

TEXTURE2D_X(_DepthPyramid);         SAMPLER(sampler_DepthPyramid);
TEXTURE2D_ARRAY(_DepthPyramidCS);   SAMPLER(sampler_DepthPyramidCS);

// CBUFFER_START(UnityPerMaterial)
    int         _Frame;
    float3      _WorldSpaceViewDir;
    float       _ThicknessScale;
    float       _EdgeFade;
    float       _StepStride;
    float       _MaxSteps;
    float       _MinSmoothness;
    float       _FadeSmoothness;
    float4      _ScreenResolution;
    int         _ReflectSky;
    int         _RandomSeed;
    float4      _SSRJitter;
    float       _BRDFBias;
    float       _TemporalScale;
    float       _TemporalBlendWeight;
// CBUFFER_END

#ifndef kMaterialFlagSpecularSetup
    #define kMaterialFlagSpecularSetup 8 // Lit material use specular setup instead of metallic setup
#endif

#ifndef kDielectricSpec
    #define kDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
#endif

static const int2 sampleOffsets[9] = 
{
    int2(-1.0, -1.0), int2(0.0, -1.0), int2(1.0, -1.0),
    int2(-1.0,  0.0), int2(0.0,  0.0), int2(1.0,  0.0),
    int2(-1.0,  1.0), int2(0.0,  1.0), int2(1.0,  1.0)
};

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

float DistanceSquared(float2 a, float2 b)
{
    return dot(a - b, a - b);
}

inline float SampleDepth(float2 uv)
{
    return SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
}

float3x3 GetTangentBasis(float3 tangentZ)
{
    float3 upVector = abs(tangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangentX = normalize(cross(upVector, tangentZ));
    float3 tangentY = cross(tangentZ, tangentX);
    return float3x3(tangentX, tangentY, tangentZ);
}

inline float4 TangentToWorld(float4 vec, float4 tangentZ)
{
    float3 T2W = mul(vec.xyz, GetTangentBasis(tangentZ.xyz));
    return float4(T2W, vec.w);
}

inline float3 GetReflectDirWS(float2 screenUV, float3 normalWS, float3 viewDirWS, float roughness, inout float PDF, inout float jitter, inout bool valid)
{
    // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    // random.y = lerp(random.y, 0.0, _BRDFBias);
    // float3 reflectDirWS = ImportanceSampleGGX_SSR(random, normalWS, viewDirWS, roughness, valid);
    // PDF = 1.0;
    // jitter = random.x + random.y;

    float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    random.y = lerp(random.y, 0.0, _BRDFBias);
    float4 H = ImportanceSampleGGX_SSR(random, roughness);
    float3x3 tangentToWorld = GetTangentBasis(normalWS);
    H.xyz = mul(H.xyz, tangentToWorld);
    float3 reflectDirWS = reflect(viewDirWS, H.xyz);

    PDF = H.w;
    jitter = random.x + random.y;

    // float3 reflectDirWS = reflect(viewDirWS, normalWS);
    // PDF = 1.0;
    // jitter = 0;

    return normalize(reflectDirWS);
}

float4 PreintegrateDFGLUT(inout float3 energyCompensation, float3 specularColor, float roughness, float NoV)
{
    float3 envFilterDFG = SAMPLE_TEXTURE2D_LOD(_BRDFLUT, sampler_BRDFLUT, float2(roughness, NoV), 0.0).rgb;
    float3 reflectionDFG = lerp(saturate(50.0 * specularColor.g) * envFilterDFG.ggg, envFilterDFG.rrr, specularColor);

    energyCompensation = 1.0 + specularColor * (1.0 / envFilterDFG.r - 1.0);

    return float4(reflectionDFG, envFilterDFG.b);
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

float2 GetMotionVector(float2 uv, float depth)
{
    float4 hitPosNDC, hitPosVS;
    float4 hitPosWS = ReconstructPositionWS(uv, depth, hitPosNDC, hitPosVS);

    float4 prevClipPos = mul(_PrevViewProjMatrix, hitPosWS);
    float4 curClipPos = mul(UNITY_MATRIX_VP, hitPosWS);

    float2 prevHPos = prevClipPos.xy / prevClipPos.w;
    float2 curHPos = curClipPos.xy / curClipPos.w;

    float2 prevVPos = prevHPos * 0.5 + 0.5;
    float2 curVPos = curHPos * 0.5 + 0.5;

    float2 motionVector = curVPos - prevVPos;

    return motionVector;
}

float4 Texture2DSampleBicubic(Texture2D tex, SamplerState texSampler, float2 uv, float2 texelSize, in float2 invSize)
{
    FCatmullRomSamples samples = GetBicubic2DCatmullRomSamples(uv, texelSize, invSize);

    float4 outColor = 0;
    for (uint i = 0; i < samples.Count; i++)
    {
        outColor += tex.SampleLevel(texSampler, samples.UV[i], 0) * samples.Weight[i];
    }
    outColor *= samples.FinalMultiplier;

    return outColor;
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

float SSRBRDF(float3 viewDirVS, float3 reflectDirVS, float3 normalVS, float roughness)
{
    float3 H = normalize(viewDirVS + reflectDirVS);

    float NoH = max(dot(normalVS, H), 0.0);
    float NoL = max(dot(normalVS, reflectDirVS), 0.0);
    float NoV = max(dot(normalVS, viewDirVS), 0.0);

    float D = D_GGX_SSR(NoH, roughness);
    float G = Vis_SmithGGXCorrelated_SSR(NoL, NoV, roughness);
    return max(0, D * G);
}

// =============== HiZ Tracing Start =============== //
inline float2 GetScreenResolution()
{
    return _ScreenResolution.xy;
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
    return SAMPLE_TEXTURE2D_ARRAY(_DepthPyramidCS, sampler_DepthPyramidCS, uv, index);
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

bool IntersectsDepthBuffer(float rayZMin, float rayZMax, float sceneZ, float thickness)
{
    return (rayZMax >= sceneZ - thickness) && (rayZMin <= sceneZ);
}

bool LinearSSTrace(float3 rayOriginVS, float3 reflectDirVS, float jitter, int stepSize, inout float2 hitUV, inout float3 hitPoint, inout float totalStep)
{
    float2 invSize = _ScreenResolution.zw;
    hitUV = -1.0;

    float thickness = _ThicknessScale * 1;
    float traceDistance = 128;
    float nearPlaneZ = -0.01;
    float rayLength = (rayOriginVS.z + reflectDirVS.z * traceDistance) > nearPlaneZ ? (nearPlaneZ - rayOriginVS.z) / reflectDirVS.z : traceDistance;
    float3 rayEndVS = rayOriginVS + rayLength * reflectDirVS;
    
    float4 H0 = mul(UNITY_MATRIX_P, float4(rayOriginVS, 1.0));
    H0.xy = (float2(H0.x, H0.y * _ProjectionParams.x) + H0.w) * 0.5;
    H0.xy *= _ScreenResolution.xy;
    float4 H1 = mul(UNITY_MATRIX_P, float4(rayEndVS, 1.0));
    H1.xy = (float2(H1.x, H1.y * _ProjectionParams.x) + H1.w) * 0.5;
    H1.xy *= _ScreenResolution.xy;

    float K0 = 1.0 / H0.w;
    float K1 = 1.0 / H1.w;
    float2 P0 = H0.xy * K0;
    float2 P1 = H1.xy * K1;
    float3 Q0 = rayOriginVS * K0;
    float3 Q1 = rayEndVS * K1;

    float xMax = _ScreenResolution.x - 0.5;
    float yMax = _ScreenResolution.y - 0.5;
    float xMin = 0.5;
    float yMin = 0.5;
    float alpha = 0;

    // 防止在屏幕边缘时出现拉伸
    UNITY_BRANCH
    if (P1.x > xMax || P1.x < xMin)
    {
        float xClip = P1.x > xMax ? xMax : xMin;
        float xAlpha = (P1.x - xClip) / (P1.x - P0.x);
        alpha = xAlpha;
    }
    UNITY_BRANCH
    if (P1.y > yMax || P1.y < yMin)
    {
        float yClip = P1.y > yMax ? yMax : yMin;
        float yAlpha = (P1.y - yClip) / (P1.y - P0.y);
        alpha = max(alpha, yAlpha);
    }

    P1 = lerp(P1, P0, alpha);
    K1 = lerp(K1, K0, alpha);
    Q1 = lerp(Q1, Q0, alpha);

    P1 = DistanceSquared(P0, P1) < 0.0001 ? P0 + float2(0.01, 0.01) : P1;
    float2 delta = P1 - P0;
    bool permute = false;
    if (abs(delta.x) < abs(delta.y))
    {
        permute = true;
        delta = delta.yx;
        P1 = P1.yx;
        P0 = P0.yx;
    }

    float stepDirection = sign(delta.x);
    float invDx = stepDirection / delta.x;
    float2 dP = float2(stepDirection, invDx * delta.y);
    float3 dQ = (Q1 - Q0) * invDx;
    float dK = (K1 - K0) * invDx;

    dP *= stepSize;
    dQ *= stepSize;
    dK *= stepSize;
    P0 += dP * jitter;
    Q0 += dQ * jitter;
    K0 += dK * jitter;

    float3 Q = Q0;
    float K = K0;
    float prevZMaxEstimate = rayOriginVS.z;
    float rayZMax = prevZMaxEstimate;
    float rayZMin = prevZMaxEstimate;
    float sceneZ = 1e+5;
    float end = P1.x * stepDirection;
    
    bool intersecting = IntersectsDepthBuffer(rayZMin, rayZMax, sceneZ, thickness);
    float2 P = P0;
    int originStepCount = 0;

    UNITY_LOOP
    for (totalStep = 0; totalStep < _MaxSteps; totalStep++)
    {
        rayZMin = prevZMaxEstimate;
        rayZMax = (dQ.z * 0.5 + Q.z) / (dK * 0.5 + K);
        prevZMaxEstimate = rayZMax;

        if (rayZMin > rayZMax)
        {
            Swap(rayZMin, rayZMax);
        }

        hitUV = permute ? P.yx : P;
        sceneZ = SampleDepth(hitUV * invSize);
        sceneZ = -LinearEyeDepth(sceneZ, _ZBufferParams);
        
        bool isBehind = rayZMin + 0.01 <= sceneZ;
        intersecting = isBehind && (rayZMax >= sceneZ - thickness);

        if (intersecting && (P.x * stepDirection) <= end) break;

        P += dP;
        Q.z += dQ.z;
        K += dK;
    }
    P -= dP;
    Q.z -= dQ.z;
    K -= dK;

    totalStep = originStepCount;
    Q.xy += dQ.xy * totalStep;
    hitPoint = Q * (1 / K);

    return intersecting;
}

/* 
inline float GetMarchSize(float2 start, float2 end, float2 samplePos)
{
    float2 dir = abs(end - start);
    return length(float2(min(dir.x, samplePos.x), min(dir.y, samplePos.y)));
}

inline float4 HizTrace(float thickness, float2 screenSize, float3 rayOrigin, float3 rayDirection)
{
    float sampleSize = GetMarchSize(rayOrigin.xy, rayOrigin.xy + rayDirection.xy, screenSize);
    float3 samplePos = rayOrigin + rayDirection * sampleSize;

    int level = HIZ_START_LEVEL;
    float mask = 0.0;

    UNITY_LOOP
    for (int i = 0; i < _MaxSteps; i++)
    {
        float2 cellCount = screenSize * exp2(level + 1);
        float newSampleSize = GetMarchSize(samplePos.xy, samplePos.xy + rayDirection.xy, cellCount);
        float3 newSamplePos = samplePos + rayDirection * newSampleSize;
        float sampleMinDepth = SAMPLE_TEXTURE2D_LOD(_DepthPyramid, sampler_DepthPyramid, newSamplePos.xy, level).r;

        UNITY_FLATTEN
        if (sampleMinDepth < newSamplePos.z)
        {
            level = min(HIZ_MAX_LEVEL, level + 1);
            samplePos = newSamplePos;
        }
        else
        {
            level--;
        }

        UNITY_BRANCH
        if (level < HIZ_STOP_LEVEL)
        {
            float sceneDepth = -LinearEyeDepth(sampleMinDepth, _ZBufferParams);
            float rayDepth = -LinearEyeDepth(samplePos.z, _ZBufferParams);
            float delta = sceneDepth - rayDepth;
            mask = delta <= thickness && i > 0;
            return float4(samplePos, mask);
        }
    }

    return float4(samplePos, mask);
} 
*/

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
            level = min(maxLevel, level + 1);
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
            //     level = HIZ_START_LEVEL + 2;
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

