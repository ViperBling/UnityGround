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

inline float3 GetReflectDirWS(float2 screenUV, float3 normalWS, float3 viewDirWS, float smoothness, inout float PDF, inout float jitter, inout bool valid)
{
    // float2 random = float2(GenerateRandomFloat(screenUV, _ScreenResolution.xy, _RandomSeed), GenerateRandomFloat(screenUV, _ScreenResolution.xy, _RandomSeed));
    // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    // random.y = lerp(random.y, 0.0, _BRDFBias);
    // float3 reflectDirWS = ImportanceSampleGGX_SSR(random, normalWS, viewDirWS, smoothness, valid);
    // PDF = 1.0;

    // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    // random.y = lerp(random.y, 0.0, _BRDFBias);
    // float4 H = ImportanceSampleGGX_SSR(random, smoothness);
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


struct FRay
{
    float3 Position;
    float3 Direction;
};

struct FHitPoint
{
    float3 Position;
    float TravelDist;
    float2 TexCoord;
    half3 Albedo;
    half3 Specular;
    half Occlusion;
    half3 Normal;
    half Smoothness;
};

FHitPoint InitializeHitPoint()
{
    FHitPoint hitPoint = (FHitPoint)0;
    hitPoint.Position = float3(0, 0, 0);
    hitPoint.TravelDist = REAL_EPS;
    hitPoint.TexCoord = float2(0, 0);
    hitPoint.Albedo = half3(0, 0, 0);
    hitPoint.Specular = half3(0, 0, 0);
    hitPoint.Occlusion = 1.0;
    hitPoint.Normal = half3(0, 0, 0);
    hitPoint.Smoothness = 0.0;
    return hitPoint;
}

float ConvertLinearEyeDepth(float deviceDepth)
{
    UNITY_BRANCH
    if (unity_OrthoParams.w == 0.0)
    {
        return LinearEyeDepth(deviceDepth, _ZBufferParams);
    }
    else
    {
        deviceDepth = 1.0 - deviceDepth;
        return lerp(_ProjectionParams.y, _ProjectionParams.z, deviceDepth);
    }
}

void HitSurfaceDataFromGBuffer(float2 screenUV, inout half3 albedo, inout half3 specular, inout half occlusion, inout half3 normal, inout half smoothness)
{
    half4 gBuffer0 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer0, sampler_point_clamp, screenUV, 0);
    half4 gBuffer1 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer1, sampler_point_clamp, screenUV, 0);
    half4 gBuffer2 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_point_clamp, screenUV, 0);

    albedo = gBuffer0.rgb;
    specular = (UnpackMaterialFlags(gBuffer0.a) == kMaterialFlagSpecularSetup) ? gBuffer1.rgb : lerp(kDielectricSpec.rgb, max(albedo.rgb, kDielectricSpec.rgb), gBuffer1.r);
    occlusion = gBuffer1.a;
    normal = UnpackNormal(gBuffer2.rgb);
    smoothness = gBuffer2.a;
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