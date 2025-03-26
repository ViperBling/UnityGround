#pragma once

#define STEP_STRIDE     _StepStride
#define NUM_STEPS       uint(_MaxSteps)

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
TEXTURE2D_X(_SSRReflectionColorTexture);
TEXTURE2D_X(_SSRTemporalHistoryTexture);
TEXTURE2D_X(_MotionVectorTexture);
float4 _MotionVectorTexture_TexelSize;

SAMPLER(sampler_BlueNoiseTexture);
SAMPLER(sampler_SSRSceneColorTexture);
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
    float4      _ScreenResolution;
    int         _ReflectSky;
    int         _RandomSeed;
    float4      _SSRJitter;
    float       _BRDFBias;
CBUFFER_END

#ifndef kMaterialFlagSpecularSetup
    #define kMaterialFlagSpecularSetup 8 // Lit material use specular setup instead of metallic setup
#endif

#ifndef kDielectricSpec
    #define kDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
#endif

static const int2 sampleOffsets[9] = {
    int2(-1.0, -1.0), int2(0.0, -1.0), int2(1.0, -1.0),
    int2(-1.0, 0.0), int2(0.0, 0.0), int2(1.0, 0.0),
    int2(-1.0, 1.0), int2(0.0, 1.0), int2(1.0, 1.0)
};

// void Swap(inout float a, inout float b)
// {
//     float temp = a;
//     a = b;
//     b = temp;
// }

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
    // float2 random = float2(GenerateRandomFloat(screenUV, _ScreenResolution.xy, _RandomSeed), GenerateRandomFloat(screenUV, _ScreenResolution.xy, _RandomSeed));
    // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    // random.y = lerp(random.y, 0.0, _BRDFBias);
    // float3 reflectDirWS = ImportanceSampleGGX_SSR(random, normalWS, viewDirWS, roughness, valid);
    // PDF = 1.0;

    // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    // random.y = lerp(random.y, 0.0, _BRDFBias);
    // float4 H = ImportanceSampleGGX_SSR(random, roughness);
    // float3x3 tangentToWorld = GetTangentBasis(normalWS);
    // H.xyz = mul(H.xyz, tangentToWorld);
    // float3 reflectDirWS = reflect(viewDirWS, H.xyz);

    // PDF = H.w;
    // jitter = random.x + random.y;
    
    // float3 viewDirTS = mul(tangentToWorld, viewDirWS);
    // float3 viewDirRough = normalize(float3(a * viewDirTS.x, a * viewDirTS.y, viewDirTS.z));
    // float lenSq = viewDirRough.x * viewDirRough.x + viewDirRough.y * viewDirRough.y;
    // float3 T1 = lenSq > 0 ? float3(-viewDirRough.y, viewDirRough.x, 0) * rsqrt(lenSq) : float3(1, 0, 0);
    // float3 T2 = cross(viewDirRough, T1);

    // float r = sqrt(random.x);
    // float phi = 2.0 * PI * random.y;
    // float t1 = r * cos(phi);
    // float t2 = r * sin(phi);
    // float s = 0.5 * (1.0 + viewDirRough.z);
    // t2 = (1.0 - s) * sqrt(1.0 - t1 * t1) + s * t2;
    // float3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * viewDirRough;
    // float3 H = normalize(float3(a * Nh.x, a * Nh.y, max(0, Nh.z)));
    // H = mul(H, tangentToWorld);
    // float3 reflectDirWS = reflect(viewDirWS, H);

    float3 reflectDirWS = reflect(viewDirWS, normalWS);
    PDF = 1.0;
    jitter = 0;

    return normalize(reflectDirWS);
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

float ScreenEdgeMask(float2 screenUV)
{
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

inline float DistanceSquared(float2 a, float2 b)
{
    return dot(a - b, a - b);
}

inline float DistanceSquared(float3 a, float3 b)
{
    return dot(a - b, a - b);
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
    float traceDistance = 512;
    float nearPlaneZ = -0.01;
    float rayLength = (rayOriginVS.z + reflectDirVS.z * traceDistance) > nearPlaneZ ? (nearPlaneZ - rayOriginVS.z) / reflectDirVS.z : traceDistance;
    float3 rayEndVS = rayOriginVS + rayLength * reflectDirVS;
    
    float4 H0 = mul(UNITY_MATRIX_P, float4(rayOriginVS, 1.0));
    float4 H1 = mul(UNITY_MATRIX_P, float4(rayEndVS, 1.0));
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

    if (P1.x > xMax || P1.x < xMin)
    {
        float xClip = P1.x > xMax ? xMax : xMin;
        float xAlpha = (P1.x - xClip) / (P1.x - P0.x);
        alpha = xAlpha;
    }
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
        sceneZ = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, hitUV * invSize, 0.0).r;
        sceneZ = -LinearEyeDepth(sceneZ, _ZBufferParams);
        
        bool isBehind = rayZMin <= sceneZ;
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
