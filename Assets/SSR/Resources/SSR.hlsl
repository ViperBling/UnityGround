#pragma once

#include "Assets/SSR/Resources/SSRCommon.hlsl"

half4 LinearSSTracingPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);

    half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;
    
    UNITY_BRANCH
    if (isBackground) return half4(0, 0, 0, 1);

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);

    // UNITY_BRANCH if (smoothness < _MinSmoothness) return half4(0, 0, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    bool valid = false;
    float PDF, jitter;
    float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, smoothness, PDF, jitter, valid);
    float3 reflectDirVS = TransformWorldToViewDir(reflectDirWS);

    
    
    return half4(positionVS.xyz, 1.0);
}

half4 HiZTracingPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

half4 SpatioFilterPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

half4 TemporalFilterPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

half4 CompositeFragmentPass(Varyings fsIn) : SV_Target
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