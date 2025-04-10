#pragma once

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

TEXTURE2D_X(_SSR_SceneColorTexture);
TEXTURE2D_X(_SSR_BlueNoiseTexture);
TEXTURE2D_X(_SSR_BRDFLUT);
TEXTURE2D_X(_SSR_ReflectionColorTexture);
TEXTURE2D_X(_SSR_TemporalHistoryTexture);
TEXTURE2D_X(_MotionVectorTexture);
float4 _MotionVectorTexture_TexelSize;

SAMPLER(sampler_SSR_SceneColorTexture);
SAMPLER(sampler_SSR_BlueNoiseTexture);
SAMPLER(sampler_SSR_BRDFLUT);
SAMPLER(sampler_SSR_ReflectionColorTexture);
SAMPLER(sampler_SSR_TemporalHistoryTexture);
SAMPLER(sampler_BlitTexture);
SAMPLER(sampler_point_clamp);

CBUFFER_START(UnityPerMaterial)
    float4      _SSR_Jitter;
    float       _SSR_BRDFBias;
    float       _SSR_NumSteps;
    float       _SSR_ScreenFade;
    float       _SSR_Thickness;
    float       _SSR_TemporalScale;
    float       _SSR_TemporalWeight;
    float4      _SSR_ScreenResolution;
    float       _SSR_RayStepStride;
    float       _SSR_TraceDistance;
    float4      _SSR_ProjectionInfo;
    float4x4    _SSR_ProjectionMatrix;
    float4x4    _SSR_ViewProjectionMatrix;
    float4x4    _SSR_PrevViewProjectionMatrix;
    float4x4    _SSR_InvProjectionMatrix;
    float4x4    _SSR_InvViewProjectionMatrix;
    float4x4    _SSR_WorldToCameraMatrix;
    float4x4    _SSR_CameraToWorldMatrix;
    float4x4    _SSR_ProjectToPixelMatrix;
CBUFFER_END

#ifndef kMaterialFlagSpecularSetup
    #define kMaterialFlagSpecularSetup 8 // Lit material use specular setup instead of metallic setup
#endif

#ifndef kDielectricSpec
    #define kDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
#endif

static const int2 sampleOffsets[9] = {
    int2(-1.0, -1.0), int2(0.0, -1.0), int2(1.0, -1.0),
    int2(-1.0,  0.0), int2(0.0,  0.0), int2(1.0, 0.0),
    int2(-1.0,  1.0), int2(0.0,  1.0), int2(1.0, 1.0)
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
    return SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, uv, 0).r;
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

inline float3 GetNormalWS(float2 uv, inout float smoothness)
{
    float4 normalGBuffer = SAMPLE_TEXTURE2D_LOD(_GBuffer2, sampler_point_clamp, uv, 0.0);
    smoothness = normalGBuffer.a;
    return UnpackNormal(normalGBuffer.xyz);
}

inline float3 GetPositionWS(float3 positionNDC, float4x4 invViewProjMatrix)
{
    float4 positionWS = mul(invViewProjMatrix, float4(positionNDC, 1.0));
    return positionWS.xyz / positionWS.w;
}

inline float3 GetPositionVS(float3 positionNDC, float4x4 invProjMatrix)
{
    float4 positionVS = mul(invProjMatrix, float4(positionNDC, 1.0));
    return positionVS / positionVS.w;
}

inline float3 ReconstructCSPosition(float4 screenTexelSize, float4 projInfo, float2 screenUV, float depth)
{
    float linearEyeZ = -LinearEyeDepth(depth, _ZBufferParams);
    float3 positionCS = float3(((screenUV * screenTexelSize.zw) * projInfo.xy + projInfo.zw) * linearEyeZ, linearEyeZ);
    return positionCS;
}

inline float3 GetRayOriginVS(float4 screenTexelSize, float4 projInfo, float2 screenUV)
{
    float3 rayOriginVS = 0;
    rayOriginVS.z = SampleDepth(screenUV);
    rayOriginVS = ReconstructCSPosition(screenTexelSize, projInfo, screenUV, rayOriginVS.z);
    return rayOriginVS;
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

float2 GetMotionVector(float2 uv, float depth)
{
    float3 hitPosNDC = float4(uv * 2.0 - 1.0, depth, 1.0);
    float4 hitPosWS = float4(GetPositionWS(hitPosNDC, _SSR_InvViewProjectionMatrix), 1.0);

    float4 prevClipPos = mul(_SSR_PrevViewProjectionMatrix, hitPosWS);
    float4 curClipPos = mul(_SSR_ViewProjectionMatrix, hitPosWS);

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

float4 PreintegrateDFGLUT(inout float3 energyCompensation, float3 specularColor, float roughness, float NoV)
{
    float3 envFilterDFG = SAMPLE_TEXTURE2D_LOD(_SSR_BRDFLUT, sampler_SSR_BRDFLUT, float2(roughness, NoV), 0.0).rgb;
    float3 reflectionDFG = lerp(saturate(50.0 * specularColor.g) * envFilterDFG.ggg, envFilterDFG.rrr, specularColor);

    energyCompensation = 1.0 + specularColor * (1.0 / envFilterDFG.r - 1.0);

    return float4(reflectionDFG, envFilterDFG.b);
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

float ScreenEdgeMask(float2 screenUV)
{
    UNITY_BRANCH
    if (_SSR_ScreenFade == 0.0)
    {
        return 1.0;
    }
    else
    {
        half fadeRcpLength = rcp(_SSR_ScreenFade);
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
    float2 invSize = _SSR_ScreenResolution.zw;
    hitUV = -1.0;

    float thickness = _SSR_Thickness * 1;
    float traceDistance = _SSR_TraceDistance;
    float nearPlaneZ = -0.01;
    float rayLength = (rayOriginVS.z + reflectDirVS.z * traceDistance) > nearPlaneZ ? (nearPlaneZ - rayOriginVS.z) / reflectDirVS.z : traceDistance;
    float3 rayEndVS = rayOriginVS + rayLength * reflectDirVS;
    
    float4 H0 = mul(_SSR_ProjectToPixelMatrix, float4(rayOriginVS, 1.0));
    float4 H1 = mul(_SSR_ProjectToPixelMatrix, float4(rayEndVS, 1.0));

    float K0 = 1.0 / H0.w;
    float K1 = 1.0 / H1.w;
    float2 P0 = H0.xy * K0;
    float2 P1 = H1.xy * K1;
    float3 Q0 = rayOriginVS * K0;
    float3 Q1 = rayEndVS * K1;

    float xMax = _SSR_ScreenResolution.x - 0.5;
    float yMax = _SSR_ScreenResolution.y - 0.5;
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

    // hitUV = P0.xy;
    // hitPoint = float3(P0, 0);
    // return false;

    for (totalStep = 0; totalStep < _SSR_NumSteps; totalStep++)
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
