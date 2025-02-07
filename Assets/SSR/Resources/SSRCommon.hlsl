#pragma once

#define STEP_STRIDE     _StepStride
#define NUM_STEPS       uint(_MaxSteps)

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

TEXTURE2D_X(_GBuffer0);         // color.rgb + materialFlags.a
TEXTURE2D_X(_GBuffer1);         // specular.rgb + oclusion.a
TEXTURE2D_X(_GBuffer2);         // normalWS.rgb + smoothness.a

#if defined(_BACKFACE_ENABLED)
TEXTURE2D_X(_SSRCameraBackFaceDepthTexture);
#endif

SAMPLER(sampler_BlitTexture);
SAMPLER(sampler_point_clamp);

#if UNITY_VERSION < 202320
float4 _BlitTexture_TexelSize;
#endif

#ifndef kMaterialFlagSpecularSetup
#define kMaterialFlagSpecularSetup 8 // Lit material use specular setup instead of metallic setup
#endif

#ifndef kDieletricSpec
#define kDieletricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
#endif

CBUFFER_START(UnityPerMaterial)
half _MinSmoothness;
half _FadeSmoothness;
half _EdgeFade;
half _Thickness;
half _StepStride;
half _MaxSteps;
half _DownSample;
CBUFFER_END

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
half3 UnpackNormal(half3 pn) { return pn; }                             // values between [-1, +1]
#endif


struct FRay
{
    float3 Position;
    float3 Direction;
};

struct FHitPoint
{
    float3  Position;
    float   TravelDist;
    float2  TexCoord;
    half3   Albedo;
    half3   Specular;
    half    Occlusion;
    half3   Normal;
    half    Smoothness;
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

FHitPoint SSRRayMarching(FRay ray, half dither, float distance)
{
    FHitPoint hitPoint = InitializeHitPoint();

    half stepStride = STEP_STRIDE;
    half thickness = _Thickness;
    half accumulateStep = 0.0;

    bool startBinarySearch = false;

    UNITY_LOOP
    for (int i = 0; i <= NUM_STEPS; i++)
    {
        accumulateStep += stepStride + stepStride * dither;

        float3 rayPositionWS = ray.Position + accumulateStep * ray.Direction;
        float3 rayPositionNDC = ComputeNormalizedDeviceCoordinatesWithZ(rayPositionWS, GetWorldToHClipMatrix());

        bool isScreenSpace = (rayPositionNDC.x > 0.0 && rayPositionNDC.x < 1.0 && rayPositionNDC.y > 0.0 && rayPositionNDC.y < 1.0);
        if (!isScreenSpace) break;

        // 当前像素点的归一化深度
        float deviceDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, rayPositionNDC.xy, 0).r;

        // 当前像素点的原生深度
        float sceneDepth = ConvertLinearEyeDepth(deviceDepth);
        // 反射向量步进的深度
        float hitDepth = ConvertLinearEyeDepth(rayPositionNDC.z);

        float depthDelta = sceneDepth - hitDepth;

        // Sign is positive : ray is in front of the actual intersection.
        // Sign is negative : ray is behind the actual intersection.
        half depthSign;
        
    #if defined(_BACKFACE_ENABLED)
        // 当前像素点的背面深度
        float deviceBackDepth = SAMPLE_TEXTURE2D_X_LOD(_SSRCameraBackFaceDepthTexture, sampler_CameraDepthTexture, rayPositionNDC.xy, 0).r;
        
        bool backDepthValid = deviceBackDepth != 0.0;
        float sceneBackDepth = ConvertLinearEyeDepth(deviceBackDepth);

        backDepthValid = backDepthValid && (sceneBackDepth > sceneDepth + thickness);

        float backDepthDelta;
        if (backDepthValid)
        {
            backDepthDelta = hitDepth - sceneBackDepth;
        }
        else
        {
            backDepthDelta = depthDelta - thickness;
        }
        
        if (hitDepth > sceneBackDepth && backDepthValid)
        {
            depthSign = FastSign(backDepthDelta);
        }
        else
        {
            depthSign = FastSign(depthDelta);
        }
    #else
        depthSign = FastSign(depthDelta);
    #endif

        startBinarySearch = startBinarySearch || (depthSign == -1) ? true : false;

        if (startBinarySearch && FastSign(stepStride) != depthSign)
        {
            stepStride = stepStride * depthSign * 0.5;
            thickness = thickness * 0.5;
        }

        bool isSky = deviceDepth == 0.0;

        bool successHit;

    #if defined(_BACKFACE_ENABLED)
        if (backDepthValid)
        {
            successHit = (depthDelta <= 0.0 && (hitDepth <= sceneBackDepth) && !isSky) ? true : false;
        }
        else
        {
            successHit = (depthDelta <= 0.0 && (depthDelta >= -thickness) && !isSky) ? true : false;
        }
    #else
        successHit = (depthDelta <= 0.0 && (depthDelta >= -thickness) && !isSky) ? true : false;
    #endif

        if (successHit)
        {
            hitPoint.TravelDist = length(rayPositionWS - ray.Position);
            hitPoint.TexCoord = rayPositionNDC.xy;
            break;
        }
        else if (!startBinarySearch)
        {
            stepStride = stepStride < STEP_STRIDE ? stepStride + STEP_STRIDE * 0.1 : stepStride;
            // thickness = thickness;
        }
    }
    return hitPoint;
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