#pragma once

#include "Assets/SSR/Resources/SSRCommon.hlsl"

float4 LinearSSTracingPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);

    float4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;
    
    UNITY_BRANCH if (isBackground) return float4(screenUV.xy, 0, 1);

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);
    float3 normalVS = TransformWorldToViewNormal(normalWS);
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    UNITY_BRANCH if (smoothness < _MinSmoothness) return float4(screenUV.xy, 0, 1);

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
    random.y = lerp(random.y, 0.0, _BRDFBias);

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
    hitUV *= _ScreenResolution.zw;

    UNITY_BRANCH
    if (hit)
    {
        hitMask = pow(1 - max(2 * totalStep / _MaxSteps - 1, 0), 2);
        hitMask *= saturate(512 - dot(hitPoint - positionVS.xyz, reflectDirVS));

        float smoothness;
        float3 rayHitNormal = GetNormalWS(hitUV, smoothness);
        float3 reflectDirWS = mul(UNITY_MATRIX_I_V, float4(reflectDirVS, 0)).xyz;
        if (dot(rayHitNormal, reflectDirWS) > 0.0) hitMask = 0.0;
    }
    hitMask = pow(hitMask * ScreenEdgeMask(hitUV), 2);

    float curDepth = SampleDepth(hitUV);
    float3 finalResult = float3(hitUV, curDepth);
    // finalResult = hit;
    return float4(finalResult, hitMask);
}

float4 HiZTracingPass(Varyings fsIn) : SV_Target
{
    return 1.0;
}

float4 SpatioFilterPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);

    // half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    // bool isBackground = rawDepth == 0.0;

    // float smoothness;
    // float3 normalWS = GetNormalWS(screenUV, smoothness);
    // float3 normalVS = TransformWorldToViewNormal(normalWS);
    // float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    // UNITY_BRANCH
    // if (smoothness < _MinSmoothness || isBackground) return 0.0;

    // float4 positionNDC, positionVS;
    // float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // float2 blueNoise = SAMPLE_TEXTURE2D_LOD(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV, 0.0) * 2.0 - 1.0;
    // float2x2 offsetRotationMatrix = float2x2(blueNoise.x, blueNoise.y, -blueNoise.y, -blueNoise.x);

    // float numWeight = 0;
    // float weight = 0;
    // float2 offsetUV = 0;
    // float2 neighborUV = 0;
    // float4 sampleColor = 0;
    // float4 reflectionColor = 0;

    // for (int i = 0; i < 9; i++)
    // {
    //     offsetUV = mul(offsetRotationMatrix, 2 * sampleOffsets[i] * _ScreenResolution.zw);
    //     neighborUV = screenUV + offsetUV;

    //     float4 hitUV = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, neighborUV, 0.0);

    //     // float sampledDepth = SampleDepth(hitUV.xy);
    //     float4 hitPosNDC, hitPosVS;
    //     float4 hitPosWS = ReconstructPositionWS(hitUV.xy, hitUV.z, hitPosNDC, hitPosVS);

    //     weight = SSRBRDF(normalize(-positionVS.xyz), normalize(hitPosVS - positionVS).xyz, normalVS, roughness);
    //     // weight = 1;
    //     sampleColor = SAMPLE_TEXTURE2D_LOD(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, hitUV.xy, 0.0);
    //     sampleColor.rgb /= 1 + Luminance(sampleColor.rgb);
    //     sampleColor.a = hitUV.w;

    //     reflectionColor += sampleColor * weight;
    //     numWeight += weight;
    // }

    // reflectionColor /= numWeight;
    // reflectionColor.rgb /= 1 - Luminance(reflectionColor.rgb);
    // reflectionColor.rgb = max(reflectionColor.rgb, 1e-5);
    // reflectionColor.a = sampleColor.a;

    // return reflectionColor;

    float4 hitUV = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0);
    float3 finalResult = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, hitUV.xy).rgb;
    finalResult = hitUV.z;
    
    return float4(finalResult.rgb, hitUV.w);
}

float4 TemporalFilterPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);

    float2 depthVelocity = SAMPLE_TEXTURE2D_LOD(_MotionVectorTexture, sampler_point_clamp, screenUV + _MotionVectorTexture_TexelSize.xy * 1.0, 0.0).xy;;

    float4 reflectUV = SAMPLE_TEXTURE2D_LOD(_SSRReflectionColorTexture, sampler_point_clamp, screenUV, 0.0);
    float hitDepth = reflectUV.z;
    float2 motionVector = GetMotionVector(reflectUV.xy, hitDepth);

    float velocityWeight = saturate(dot(normalWS, float3(0, 1, 0)));
    float2 velocity = lerp(depthVelocity, motionVector, velocityWeight);

    float ssrVariance = 0;
    float4 ssrCurColor = 0;
    float4 colorMin = 0;
    float4 colorMax = 0;

    float4 sampledColors[9];

    for (uint i = 0; i < 9; i++)
    {
        sampledColors[i] = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV + sampleOffsets[i] * _ScreenResolution.zw);
        // sampledColors[i] = Texture2DSampleBicubic(_BlitTexture, sampler_BlitTexture, screenUV + sampleOffsets[i] * _ScreenResolution.zw, _ScreenResolution.xy, _ScreenResolution.zw);
    }
    
    // float sampleWeights[9];
    // for (uint j = 0; j < 9; j++)
    // {
    //     sampleWeights[j] = HDRWeight4(sampledColors[j].rgb, 0);
    // }
    // float totalWeight = 0;
    // for (uint k = 0; k < 9; k++)
    // {
    //     totalWeight += sampleWeights[k];
    // }
    // sampledColors[4] = sampledColors[0] * sampledColors[0] + 
    //                    sampledColors[1] * sampledColors[1] + 
    //                    sampledColors[2] * sampledColors[2] + 
    //                    sampledColors[3] * sampledColors[3] + 
    //                    sampledColors[4] * sampledColors[4] + 
    //                    sampledColors[5] * sampledColors[5] + 
    //                    sampledColors[6] * sampledColors[6] + 
    //                    sampledColors[7] * sampledColors[7] + 
    //                    sampledColors[8] * sampledColors[8];
    // sampledColors[4] /= totalWeight;

    float4 m1 = 0.0;
    float4 m2 = 0.0;
    for (uint x = 0; x < 9; x++)
    {
        m1 += sampledColors[x];
        m2 += sampledColors[x] * sampledColors[x];
    }

    float4 mean = m1 / 9.0;
    float4 stdDev = sqrt(m2 / 9.0 - pow(mean, 2));

    colorMin = mean - 1.25 * stdDev;
    colorMax = mean + 1.25 * stdDev;

    ssrCurColor = sampledColors[4];
    colorMin = min(colorMin, ssrCurColor);
    colorMax = max(colorMax, ssrCurColor);

    float4 totalVariance = 0.0;
    for (uint i = 0; i < 9; i++)
    {
        totalVariance += pow(Luminance(sampledColors[i]) - Luminance(mean), 2);
    }
    ssrVariance = saturate((totalVariance/ 9) * 256);
    ssrVariance *= ssrCurColor.a;
    
    float4 prevColor = SAMPLE_TEXTURE2D_LOD(_SSRTemporalHistoryTexture, sampler_point_clamp, screenUV - velocity, 0.0);
    prevColor = clamp(prevColor, colorMin, colorMax);

    float temporalBlendWeight = saturate(1 - length(velocity) * 8 * 0.99);
    float4 reflectionColor = lerp(ssrCurColor, prevColor, temporalBlendWeight);

    // float4 curColor = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0);
    // float3 result = curColor.xyz;
    // return float4(result, 1.0);
    return reflectionColor;
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    float rawDepth = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV, 0.0).r;
    half4 sceneColor = SAMPLE_TEXTURE2D_LOD(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, screenUV, 0.0);

    UNITY_BRANCH
    if (rawDepth == 0.0) return sceneColor;

    // half3 albedo;
    // half3 specular;
    // half occlusion;
    // half3 normal;
    // half smoothness;
    // HitDataFromGBuffer(screenUV, albedo, specular, occlusion, normal, smoothness);
    
    float4 reflectedColor = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0);

    // half3 reflectedColor = SAMPLE_TEXTURE2D_LOD(_SSRSceneColorTexture, sampler_point_clamp, reflectedUV.xy, 0.0).rgb;
    // half3 reflectedColor = reflectedUV.xyz;

    // reflectedColor *= occlusion;
    // half reflectivity = ReflectivitySpecular(specular);

    // half fresnel = (max(smoothness, 0.04) - 0.04) * Pow4(1.0 - saturate(dot(normal, _WorldSpaceViewDir))) + 0.04;
    // reflectedColor = lerp(reflectedColor, reflectedColor * specular, saturate(reflectivity - fresnel));
    
    // half3 finalColor = lerp(sceneColor.xyz, reflectedColor.xyz,/*  saturate(reflectivity + fresnel) *  */reflectedColor.w);
    // finalColor = reflectedColor.xyz;
    float3 finalColor = sceneColor.rgb + reflectedColor.rgb * reflectedColor.a;
    finalColor = reflectedColor.rgb;
    
    return half4(finalColor, 1.0);
}