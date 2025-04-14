#pragma once

#include "Assets/SSR/Resources/SSRCommon.hlsl"

float4 LinearSSTracingPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);
    // UNITY_BRANCH if (rawDepth == 0.0) return float4(screenUV, 0, 0);

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);
    float3 normalVS = mul((float3x3)_SSR_WorldToCameraMatrix, normalWS);
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);
    
    UNITY_BRANCH if (roughness > 0.8) return float4(screenUV, 0, 0);

    float3 positionNDC = float3(screenUV * 2 - 1, rawDepth);
    float3 positionWS = GetPositionWS(positionNDC, _SSR_InvViewProjectionMatrix);
    float3 positionVS = GetPositionVS(positionNDC, _SSR_InvProjectionMatrix);
    float3 viewDirWS = normalize(positionWS - _WorldSpaceCameraPos);

    float4 screenTexelSize = _SSR_ScreenResolution.zwxy;
    float3 rayOriginVS = GetRayOriginVS(screenTexelSize, _SSR_ProjectionInfo, screenUV);
    float rayBump = max(-0.01 * rayOriginVS.z, 0.001);

    float2 noiseUV = (screenUV + _SSR_Jitter.zw) * _SSR_ScreenResolution.xy / 1024;
    float2 random = SAMPLE_TEXTURE2D(_SSR_BlueNoiseTexture, sampler_SSR_BlueNoiseTexture, noiseUV).xy;
    float jitter = random.x + random.y;
    random.y = lerp(random.y, 0.0, _SSR_BRDFBias);

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

    UNITY_BRANCH if (reflectDirVS.z > 0) return float4(screenUV, 0, 0);

    float totalStep = 0;
    float hitMask = 0.0;
    float2 hitUV = 0.0;
    float3 hitPoint = 0.0;
    bool hit = LinearSSTrace(rayOriginVS + rayBump * normalVS, reflectDirVS, jitter, _SSR_RayStepStride, hitUV, hitPoint, totalStep);
    hitUV *= _SSR_ScreenResolution.zw;

    UNITY_BRANCH
    if (hit)
    {
        hitMask = pow(1 - max(2 * totalStep / _SSR_NumSteps - 1, 0), 2);
        hitMask *= saturate(_SSR_TraceDistance - dot(hitPoint - positionVS.xyz, reflectDirVS));

        float smoothness;
        float3 rayHitNormal = GetNormalWS(hitUV, smoothness);
        float3 reflectDirWS = mul(_SSR_CameraToWorldMatrix, float4(reflectDirVS, 0)).xyz;
        if (dot(rayHitNormal, reflectDirWS) > 0.0) hitMask = 0.0;
    }
    else
    {
        hitUV = screenUV;
    }
    hitMask = pow(hitMask * ScreenEdgeMask(hitUV), 2);

    float curDepth = SampleDepth(hitUV);
    float3 finalResult = float3(hitUV, curDepth);
    // float3 finalResult = 0.0;
    // finalResult = hitMask;
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
    // UNITY_BRANCH if (rawDepth == 0.0) return float4(screenUV, 0, 0);

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);
    float3 normalVS = normalize(mul((float3x3)_SSR_WorldToCameraMatrix, normalWS));
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);
    // UNITY_BRANCH if (roughness > 0.8) return float4(screenUV, 0, 0);

    float3 positionNDC = float3(screenUV * 2 - 1, rawDepth);
    float3 positionWS = GetPositionWS(positionNDC, _SSR_InvViewProjectionMatrix);
    float3 positionVS = GetPositionVS(positionNDC, _SSR_InvProjectionMatrix);

    float2 noiseUV = (screenUV + _SSR_Jitter.zw) * _SSR_ScreenResolution.xy / 1024;
    float2 blueNoise = SAMPLE_TEXTURE2D(_SSR_BlueNoiseTexture, sampler_SSR_BlueNoiseTexture, noiseUV) * 2.0 - 1.0;
    float2x2 offsetRotationMatrix = float2x2(blueNoise.x, blueNoise.y, -blueNoise.y, -blueNoise.x);

    float numWeight = 0;
    float weight = 0;
    float2 offsetUV = 0;
    float2 neighborUV = 0;
    float4 sampleColor = 0;
    float4 reflectionColor = 0;

    for (int i = 0; i < 9; i++)
    {
        // offsetUV = mul(offsetRotationMatrix, 2 * sampleOffsets[i] * _SSR_ScreenResolution.zw);
        offsetUV = 2 * sampleOffsets[i] * _SSR_ScreenResolution.zw;
        neighborUV = screenUV + offsetUV;

        float4 hitUV = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, neighborUV, 0.0);

        float3 hitPosNDC = float3(hitUV.xy * 2 - 1, hitUV.z);
        float3 hitPosVS = GetPositionVS(hitPosNDC, _SSR_InvProjectionMatrix);

        weight = SSRBRDF(normalize(-positionVS.xyz), normalize(hitPosVS - positionVS), normalVS, roughness);
        // weight = 1;
        sampleColor = SAMPLE_TEXTURE2D_LOD(_SSR_SceneColorTexture, sampler_SSR_SceneColorTexture, hitUV.xy, 0.0);
        sampleColor.rgb /= 1 + Luminance(sampleColor.rgb);
        sampleColor.a = hitUV.w;

        reflectionColor += sampleColor * weight;
        numWeight += weight;
    }

    reflectionColor /= numWeight;
    reflectionColor.rgb /= 1 - Luminance(reflectionColor.rgb);
    reflectionColor.rgb = max(reflectionColor.rgb, 1e-5);

    return reflectionColor;

    // float4 hitUV = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0);
    // float3 hitPosNDC = float3(hitUV.xy * 2 - 1, hitUV.z);
    // float3 hitPosVS = GetPositionVS(hitPosNDC, _SSR_InvProjectionMatrix);

    // weight = SSRBRDF(normalize(-positionVS.xyz), normalize(hitPosVS - positionVS), normalVS, roughness);
    // float3 finalResult = SAMPLE_TEXTURE2D_LOD(_SSR_SceneColorTexture, sampler_SSR_SceneColorTexture, hitUV.xy, 0.0);
    // finalResult *= weight;
    
    // return float4(finalResult.rgb, hitUV.w);
}

float4 TemporalFilterPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);

    float2 depthVelocity = SAMPLE_TEXTURE2D_LOD(_MotionVectorTexture, sampler_point_clamp, screenUV, 0.0).xy;;

    float4 reflectUV = SAMPLE_TEXTURE2D_LOD(_SSR_ReflectionColorTexture, sampler_SSR_ReflectionColorTexture, screenUV, 0.0);
    float hitDepth = reflectUV.z;
    float2 motionVector = GetMotionVector(reflectUV.xy, hitDepth);

    float velocityWeight = saturate(dot(normalWS, float3(0, 1, 0)));
    float2 velocity = lerp(-depthVelocity, motionVector, velocityWeight);

    float ssrVariance = 0;
    float4 ssrCurColor = 0;
    float4 colorMin = 0;
    float4 colorMax = 0;

    float4 sampledColors[9];

    for (uint i = 0; i < 9; i++)
    {
        // sampledColors[i] = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV + sampleOffsets[i] * _SSR_ScreenResolution.zw);
        sampledColors[i] = Texture2DSampleBicubic(_BlitTexture, sampler_BlitTexture, screenUV + sampleOffsets[i] * _SSR_ScreenResolution.zw, _SSR_ScreenResolution.xy, _SSR_ScreenResolution.zw);
    }
    
    float sampleWeights[9];
    for (uint j = 0; j < 9; j++)
    {
        sampleWeights[j] = HDRWeight4(sampledColors[j].rgb, 10);
    }
    float totalWeight = 0;
    for (uint k = 0; k < 9; k++)
    {
        totalWeight += sampleWeights[k];
    }
    sampledColors[4] = sampledColors[0] * sampleWeights[0] + 
                       sampledColors[1] * sampleWeights[1] + 
                       sampledColors[2] * sampleWeights[2] + 
                       sampledColors[3] * sampleWeights[3] + 
                       sampledColors[4] * sampleWeights[4] + 
                       sampledColors[5] * sampleWeights[5] + 
                       sampledColors[6] * sampleWeights[6] + 
                       sampledColors[7] * sampleWeights[7] + 
                       sampledColors[8] * sampleWeights[8];
    sampledColors[4] /= totalWeight;

    float4 m1 = 0.0;
    float4 m2 = 0.0;
    for (uint x = 0; x < 9; x++)
    {
        m1 += sampledColors[x];
        m2 += sampledColors[x] * sampledColors[x];
    }

    float4 mean = m1 / 9.0;
    float4 stdDev = sqrt(m2 / 9.0 - pow(mean, 2));

    colorMin = mean - _SSR_TemporalScale * stdDev;
    colorMax = mean + _SSR_TemporalScale * stdDev;

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
    
    float4 prevColor = SAMPLE_TEXTURE2D_LOD(_SSR_TemporalHistoryTexture, sampler_SSR_TemporalHistoryTexture, screenUV - velocity, 0.0);
    prevColor = clamp(prevColor, colorMin, colorMax);

    float temporalBlendWeight = saturate(1 - length(velocity) * 8 * _SSR_TemporalWeight);
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
    half4 sceneColor = SAMPLE_TEXTURE2D_LOD(_SSR_SceneColorTexture, sampler_SSR_SceneColorTexture, screenUV, 0.0);

    UNITY_BRANCH
    if (rawDepth == 0.0) return sceneColor;

    float3 albedo;
    float3 specularColor;
    float occlusion;
    float3 normalWS;
    float smoothness;
    HitDataFromGBuffer(screenUV, albedo, specularColor, occlusion, normalWS, smoothness);
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    float3 positionNDC = float3(screenUV * 2 - 1, rawDepth);
    float3 positionWS = GetPositionWS(positionNDC, _SSR_InvViewProjectionMatrix);
    float3 positionVS = GetPositionVS(positionNDC, _SSR_InvProjectionMatrix);
    float3 viewDirWS = normalize(positionWS - _WorldSpaceCameraPos);

    float NoV = saturate(dot(-viewDirWS, normalWS.xyz));
    float3 eneryCompensation;
    float4 preintegrateDFG = PreintegrateDFGLUT(eneryCompensation, specularColor.rgb, roughness, NoV) * 2;
    
    float4 reflectedColor = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0);
    float hitMask = reflectedColor.w;
    // reflectedColor = reflectedColor * hitMask;
    
    float4 finalColor = lerp(sceneColor, reflectedColor, hitMask * saturate(preintegrateDFG));
    // finalColor = preintegrateDFG;
    return finalColor;
}