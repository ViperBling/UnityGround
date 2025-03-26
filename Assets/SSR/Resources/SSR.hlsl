#pragma once

#include "Assets/SSR/Resources/SSRCommon.hlsl"

float4 LinearSSTracingPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);

    float4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;
    
    UNITY_BRANCH
    if (isBackground) return float4(0, 0, 0, 1);

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);
    float3 normalVS = TransformWorldToViewNormal(normalWS);
    float roughness = clamp(1.0 - smoothness, 0.02, 1.0);

    UNITY_BRANCH if (smoothness < _MinSmoothness) return float4(0, 0, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);
    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);

    // bool valid = false;
    // float PDF, jitter;
    // float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, smoothness, PDF, jitter, valid);
    // float3 reflectDirVS = TransformWorldToViewDir(reflectDirWS);

    float3 rayOriginVS = positionVS.xyz;
    float rayBump = max(-0.01 * rayOriginVS.z, 0.001);

    float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV).xy;
    float jitter = random.x + random.y;

    float4 H = 0.0;
    if (roughness > 0.1)
    {
        H = TangentToWorld(ImportanceSampleGGX_SSR(random, roughness), float4(normalVS, 1.0));
    }
    else
    {
        H = float4(normalVS, 1.0);
    }
    float3 reflectDirVS = reflect(normalize(positionVS.xyz), H.xyz);

    UNITY_BRANCH
    if (reflectDirVS.z > 0) return 0.0;

    float totalStep = 0;
    float hitMask = 0.0;
    float2 hitUV = 0.0;
    float3 hitPoint = 0.0;
    bool hit = LinearSSTrace(rayOriginVS + rayBump * normalVS, reflectDirVS, jitter, _StepStride, hitUV, hitPoint, totalStep);

    float3 finalResult = float3(hitUV, hitMask);
    return float4(finalResult, 1.0);
}

float4 HiZTracingPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

float4 SpatioFilterPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

float4 TemporalFilterPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;
    half4 sceneColor = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_point_clamp, screenUV);

    // UNITY_BRANCH
    // if (rawDepth == 0.0) return sceneColor;

    // half3 albedo;
    // half3 specular;
    // half occlusion;
    // half3 normal;
    // half smoothness;
    // HitDataFromGBuffer(screenUV, albedo, specular, occlusion, normal, smoothness);
    
    float4 reflectedUV = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV);

    // half3 reflectedColor = SAMPLE_TEXTURE2D_LOD(_SSRSceneColorTexture, sampler_point_clamp, reflectedUV.xy, 0.0).rgb;
    // half3 reflectedColor = reflectedUV.xyz;

    // reflectedColor *= occlusion;
    // half reflectivity = ReflectivitySpecular(specular);

    // half fresnel = (max(smoothness, 0.04) - 0.04) * Pow4(1.0 - saturate(dot(normal, _WorldSpaceViewDir))) + 0.04;
    // reflectedColor = lerp(reflectedColor, reflectedColor * specular, saturate(reflectivity - fresnel));
    
    half3 finalColor = 0.0;

    finalColor = reflectedUV.xyz;
    
    return half4(finalColor, 1.0);
}