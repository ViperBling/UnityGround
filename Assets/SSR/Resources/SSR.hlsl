#pragma once

#include "Assets/SSR/Resources/SSRCommon.hlsl"

half4 SSRFragment(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);

    float2 screenUV = fsIn.texcoord;

    float rawDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV, 0).r;
    
    // #if !UNITY_REVERSED_Z
    // rawDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1, rawDepth);
    // #endif
    
    bool isBackground = rawDepth == 0.0 ? true : false;
    
    // #if (UNITY_REVERSED_Z == 1)
        // isBackground = rawDepth == 0.0 ? true : false;
    // #else
    //     isBackground = rawDepth == 1.0 ? true : false;
    // #endif

    half4 sceneColor = half4(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0).rgb, 0.0);

    UNITY_BRANCH
    if (isBackground)
    {
        return sceneColor;
    }

    half4 normalGBuffer = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_point_clamp, screenUV, 0);
    half smoothness = normalGBuffer.w;
    half3 normalWS = UnpackNormal(normalGBuffer.xyz);

    UNITY_BRANCH
    if (smoothness < _MinSmoothness)
    {
        return sceneColor;
    }

    float3 positionWS = ComputeWorldSpacePosition(screenUV, rawDepth, UNITY_MATRIX_I_VP);

    half3 invViewDirWS;
    if (unity_OrthoParams.w == 0.0)
    {
        invViewDirWS = normalize(positionWS - _WorldSpaceCameraPos);
    }
    else
    {
        invViewDirWS = -normalize(UNITY_MATRIX_V[2].xyz);
    }

    FRay ray = (FRay)0;
    ray.Position = positionWS;
    ray.Direction = reflect(invViewDirWS, normalWS);

    FHitPoint hitPoint = SSRRayMarching(ray, 0.0, length(rawDepth));

    half3 finalColor;
    
    UNITY_BRANCH
    if (hitPoint.TravelDist > REAL_EPS)
    {
        FHitPoint screenHit = (FHitPoint)0;
        HitSurfaceDataFromGBuffer(screenUV, screenHit.Albedo, screenHit.Specular, screenHit.Occlusion, screenHit.Normal, screenHit.Smoothness);

        half3 reflectColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, hitPoint.TexCoord, 0.0).rgb;

        sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);

        half fresnel = (max(screenHit.Smoothness, 0.04) - 0.04) * Pow4(1.0 - saturate(dot(screenHit.Normal, -invViewDirWS))) + 0.04;
        // reflectColor *= screenHit.Occlusion;

        half reflectivity = ReflectivitySpecular(screenHit.Specular);
        // reflectColor = lerp(reflectColor, reflectColor * screenHit.Specular, saturate(reflectivity - fresnel));

        half smoothnessLerp = saturate(reflectivity + fresnel);
        smoothnessLerp = 1.0;
        
        finalColor = lerp(sceneColor, reflectColor, smoothnessLerp * ScreenEdgeMask(screenUV));
    }
    else
    {
        finalColor = sceneColor;
    }
    
    return half4(finalColor, 1.0);
}

half4 CompositeFragment(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);

    float2 screenUV = fsIn.texcoord;

    float deviceDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV, 0).r;

    bool isBackground = deviceDepth == 0.0;

    // if (isBackground) return 0.0;

    half4 normalGBuffer = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_point_clamp, screenUV, 0);
    half smoothness = normalGBuffer.w;
    half3 normalWS = UnpackNormal(normalGBuffer.xyz);
    
    half fadeSmoothness = (_FadeSmoothness < smoothness) ? 1.0 : (smoothness - _MinSmoothness) * rcp(_FadeSmoothness - _MinSmoothness);

    half smoothness2 = smoothness * smoothness;
    half smoothness4 = smoothness2 * smoothness2;

#if defined(_SSR_APPROX_COLOR_MIPMAP)
    half oneMinusSmoothness4 = 1.0 - smoothness4;
    half3 reflectColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, oneMinusSmoothness4 * 1.0).rgb;
#else
    half3 reflectColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0).rgb;
#endif
    
    return half4(reflectColor, 1.0);
}