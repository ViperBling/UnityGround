#pragma once

#include "Assets/ArtSSR/Shaders/Common/ArtSSRCommon.hlsl"

//#region ViewSpaceTracingPass
float4 LinearVSTracingPass(Varyings fsIn) : SV_Target
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
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    UNITY_BRANCH
    if (smoothness < _MinSmoothness) return half4(0, 0, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    bool valid = false;
    float PDF, jitter;
    float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, roughness, PDF, jitter, valid);
    float3 reflectDirVS = mul(UNITY_MATRIX_V, float4(reflectDirWS, 0)).xyz;

    float VoR = saturate(dot(viewDirWS, reflectDirWS));
    float camVoR = saturate(dot(_WorldSpaceViewDir, reflectDirWS));

    // 越界检测，超过thickness认为在物体内部
    float thickness = _StepStride * _ThicknessScale;
    float oneMinusVoR = sqrt(1 - VoR);
    float scaledStepStride = _StepStride / oneMinusVoR;
    thickness /= oneMinusVoR;

    float maxRayLength = _MaxSteps * scaledStepStride;
    float maxDist = lerp(min(positionVS.z, maxRayLength), maxRayLength, camVoR);
    float fixNumStep = max(maxDist / scaledStepStride, 0);

    float3 curPositionVS = positionVS.xyz;
    float2 curScreenTexCoord = screenUV;

    int hit = 0;
    float maskOut = 1;
    
    // 步进方向
    float3 rayDir = reflectDirVS * scaledStepStride;
    float depthDelta = 0;

    UNITY_LOOP
    for (int i = 0; i < fixNumStep; i++)
    {
        curPositionVS += rayDir;

        // 根据当前相机空间坐标计算投影坐标
        float4 curPositionCS = mul(GetViewToHClipMatrix(), float4(curPositionVS, 1.0));
        // 替换UNITY_UV_STARTS_AT_TOP宏取反
        curPositionCS.y *= _ProjectionParams.x;
        // 除以w得到归一化设备坐标
        curPositionCS *= rcp(curPositionCS.w);
        float2 texCoord = curPositionCS.xy;
        texCoord.xy = texCoord.xy * 0.5 + 0.5;

        UNITY_BRANCH
        if (texCoord.x < 0 || texCoord.x > 1 || texCoord.y < 0 || texCoord.y > 1) break;

        // 当前步进位置的深度
        float sampledDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, texCoord.xy).r;

        UNITY_BRANCH
        if (abs(sampledDepth - rawDepth) > 0.0 && sampledDepth != 0)
        {
            // 当前位置深度图中的深度
            float sceneDepth = LinearEyeDepth(sampledDepth, _ZBufferParams);
            // 当前位置的步进深度
            float hitDepth = LinearEyeDepth(curPositionCS.z, _ZBufferParams);
            // 步进深度较大时，说明已经碰到物体，相交了
            depthDelta = hitDepth - sceneDepth;

            // float backFaceDepth = SAMPLE_TEXTURE2D(_SSRCameraBackFaceDepthTexture, sampler_point_clamp, texCoord.xy).r;
            // backFaceDepth = LinearEyeDepth(backFaceDepth, _ZBufferParams);
            // float objectDepthDelta = abs(hitDepth - backFaceDepth);
            
            UNITY_BRANCH
            if (depthDelta > 0 && depthDelta < thickness)
            {
                hit = 1;
                curScreenTexCoord = texCoord.xy;
                break;
            }
        }
    }

    UNITY_BRANCH
    if (depthDelta > thickness) hit = 0;
    
    int binaryStepCount = BINARY_STEP_COUNT * hit;
    
    UNITY_LOOP
    for (int i = 0; i < binaryStepCount; i++)
    {
        rayDir *= 0.5f;
        UNITY_FLATTEN
        if (depthDelta > 0) curPositionVS -= rayDir;
        else if (depthDelta < 0) curPositionVS += rayDir;
        else break;
            
        float4 curPositionCS = mul(GetViewToHClipMatrix(), float4(curPositionVS, 1.0));
        curPositionCS.y *= _ProjectionParams.x;
        // 除以w得到归一化设备坐标
        curPositionCS *= rcp(curPositionCS.w);
        float2 texCoord = curPositionCS.xy;
        texCoord.xy = texCoord.xy * 0.5 + 0.5;
        
        maskOut = ScreenEdgeMask(texCoord.xy);
        curScreenTexCoord = texCoord.xy;
        
        float sampledDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_point_clamp, texCoord.xy).r;
        float backFaceDepth = SAMPLE_TEXTURE2D(_SSRCameraBackFaceDepthTexture, sampler_point_clamp, texCoord.xy).r;

        float sceneDepth = LinearEyeDepth(sampledDepth, _ZBufferParams);
        float hitDepth = LinearEyeDepth(curPositionCS.z, _ZBufferParams);
        // float linearBackFaceDepth = LinearEyeDepth(backFaceDepth, _ZBufferParams);
        // float objectDepthDelta = abs(sceneDepth - linearBackFaceDepth);
        
        depthDelta = hitDepth - sceneDepth;
        
        float minV = 1.0 / max(oneMinusVoR * float(i), 0.001);
        if (abs(depthDelta) > minV)
        {
            hit = 0;
            break;
        }
    }
    float3 curNormalWS = UnpackNormal(SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, curScreenTexCoord).xyz);
    float backFaceDot = dot(curNormalWS, reflectDirWS);
    UNITY_FLATTEN
    if (backFaceDot > 0) hit = 0;

    float3 deltaDir = positionVS.xyz - curPositionVS;
    float progress = dot(deltaDir, deltaDir) / (maxDist * maxDist);
    progress = Smootherstep(0.0, 0.5, 1 - progress);

    maskOut *= hit * progress;

    float curDepth = SampleDepth(curScreenTexCoord.xy);
    float3 finalResult = float3(curScreenTexCoord.xy, curDepth);
    
    return float4(finalResult, maskOut);
}
//#endregion

//#region SSTracingPass
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
//#endregion

//#region HiZTracePass
float4 HiZTracingPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);

    half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;
    
    UNITY_BRANCH
    if (isBackground) return half4(screenUV.xy, 0, 1);

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);
    float3 normalVS = TransformWorldToViewNormal(normalWS);
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    UNITY_BRANCH
    if (smoothness < _MinSmoothness || isBackground) return half4(screenUV.xy, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos.xyz);

    bool valid = false;
    float PDF, jitter;
    float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, roughness, PDF, jitter, valid);
    float3 reflectDirVS = TransformWorldToViewDir(reflectDirWS);

    // positionVS的z轴为负，所以要取反才能得到正确的反射位置
    float3 reflectionEndPosVS = positionVS.xyz - reflectDirVS * positionVS.z * 10;
    float4 reflectionEndPosCS = mul(UNITY_MATRIX_P, float4(reflectionEndPosVS, 1.0));
    reflectionEndPosCS *= rcp(reflectionEndPosCS.w);
    reflectionEndPosCS.z = 1 - reflectionEndPosCS.z;
    positionNDC.z = 1 - positionNDC.z;
    
    // TextureSpace下的反射方向
    float3 reflectDirSS = normalize(reflectionEndPosCS - positionNDC).xyz;
    // 缩放向量到[0, 1]范围
    reflectDirSS.xy *= float2(0.5, -0.5);

    // TS下的采样位置
    float3 rayOrigin = float3(screenUV, positionNDC.z);

    // 越界检测，超过thickness认为在物体内部
    float thickness = _ThicknessScale * 0.01;
    float numSteps = _MaxSteps;

    float hit = 0;
    float camVoR = saturate(dot(_WorldSpaceViewDir, reflectDirWS));

    float iterations;
    bool isSky;
    float3 intersectPoint = HizTrace(thickness, rayOrigin, reflectDirSS, numSteps, hit, iterations, isSky);

    float edgeMask = ScreenEdgeMask(intersectPoint.xy);
    float maskOut = hit * edgeMask;
    maskOut *= maskOut;

    float curDepth = SampleDepth(intersectPoint.xy);

    float3 finalResult = float3(intersectPoint.xy, curDepth);

    return half4(finalResult, maskOut);
}
//#endregion

//#region SpatioFilterPass
float4 SpatioFilterPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float rawDepth = SampleDepth(screenUV);

    half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);
    float3 normalVS = TransformWorldToViewNormal(normalWS);
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    UNITY_BRANCH
    if (smoothness < _MinSmoothness || isBackground) return 0.0;

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    float2 blueNoise = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV) * 2.0 - 1.0;
    float2x2 offsetRotationMatrix = float2x2(blueNoise.x, blueNoise.y, -blueNoise.y, -blueNoise.x);

    float numWeight = 0;
    float weight = 0;
    float2 offsetUV = 0;
    float2 neighborUV = 0;
    float4 sampleColor = 0;
    float4 reflectionColor = 0;

    for (int i = 0; i < 9; i++)
    {
        offsetUV = mul(offsetRotationMatrix, 2 * sampleOffsets[i] * _ScreenResolution.zw);
        neighborUV = screenUV + 0;

        float4 hitUV = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, neighborUV, 0.0);

        // float sampledDepth = SampleDepth(hitUV.xy);
        float4 hitPosNDC, hitPosVS;
        float4 hitPosWS = ReconstructPositionWS(hitUV.xy, hitUV.z, hitPosNDC, hitPosVS);

        weight = SSRBRDF(normalize(-positionVS.xyz), normalize(hitPosVS - positionVS).xyz, normalVS, smoothness);
        // float3 viewDirWS = normalize(hitPosWS.xyz - _WorldSpaceCameraPos);
        // float3 reflectDirWS = reflect(viewDirWS, normalWS);
        // weight = SSRBRDF(viewDirWS, reflectDirWS, normalWS, roughness);
        // weight = 1;
        sampleColor = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, hitUV.xy);
        sampleColor.rgb /= 1 + Luminance(sampleColor.rgb);
        sampleColor.a = saturate(pow(hitUV.w, 4) * 2);

        reflectionColor += sampleColor * weight;
        numWeight += weight;
    }

    reflectionColor /= numWeight;
    reflectionColor.rgb /= 1 - Luminance(reflectionColor.rgb);
    reflectionColor.rgb = max(reflectionColor.rgb, 1e-5);

    // return reflectionColor;

    float4 hitUV = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0.0);
    float4 finalResult = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, hitUV.xy);
    
    return float4(finalResult.xyz, hitUV.w);
}
//#endregion

//#region TemporalFilterPass
float4 TemporalFilterPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    float smoothness;
    float3 normalWS = GetNormalWS(screenUV, smoothness);

    float2 depthVelocity = SAMPLE_TEXTURE2D(_MotionVectorTexture, sampler_point_clamp, screenUV + _MotionVectorTexture_TexelSize.xy * 1.0).xy;;

    float4 reflectUV = SAMPLE_TEXTURE2D(_SSRReflectionColorTexture, sampler_point_clamp, screenUV);
    float hitDepth = SampleDepth(reflectUV.xy);
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
        // sampledColors[i] = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV + sampleOffsets[i] * _ScreenResolution.zw);
        float4 bicubicSize = _ScreenResolution;
        sampledColors[i] = Texture2DSampleBicubic(_BlitTexture, sampler_BlitTexture, screenUV + (sampleOffsets[i] / _ScreenResolution), _ScreenResolution.xy, _ScreenResolution.zw);
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

    colorMin = mean - _TemporalScale * stdDev;
    colorMax = mean + _TemporalScale * stdDev;

    ssrCurColor = sampledColors[4];
    colorMin = min(colorMin, ssrCurColor);
    colorMax = max(colorMax, ssrCurColor);

    // float4 totalVariance = 0.0;
    // for (uint i = 0; i < 9; i++)
    // {
    //     totalVariance += pow(Luminance(sampledColors[i]) - Luminance(mean), 2);
    // }
    // ssrVariance = saturate((totalVariance/ 9) * 256);
    // ssrVariance *= ssrCurColor.a;
    
    float4 prevColor = SAMPLE_TEXTURE2D(_SSRTemporalHistoryTexture, sampler_point_clamp, screenUV - velocity);
    prevColor = clamp(prevColor, colorMin, colorMax);

    float temporalBlendWeight = saturate(1 - length(velocity) * 8 * _TemporalBlendWeight);
    float4 reflectionColor = lerp(ssrCurColor, prevColor, temporalBlendWeight);

    // float4 curColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV);
    // float3 result = curColor.xyz;
    // return float4(result, 1.0);
    return reflectionColor;
}
//#endregion

//#region CompositeFragmentPass
float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    float rawDepth = SampleDepth(screenUV);
    float4 sceneColor = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_point_clamp, screenUV);

    UNITY_BRANCH
    if (rawDepth == 0.0) return sceneColor;

    float3 albedo;
    float3 specularColor;
    float occlusion;
    float3 normalWS;
    float smoothness;
    HitDataFromGBuffer(screenUV, albedo, specularColor, occlusion, normalWS, smoothness);
    float roughness = clamp(1.0 - smoothness, 0.01, 1.0);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);
    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);

    float NoV = saturate(dot(-viewDirWS, normalWS.xyz));
    float3 eneryCompensation;
    float4 preintegrateDFG = PreintegrateDFGLUT(eneryCompensation, specularColor.rgb, roughness, NoV);
    
    float4 reflectedColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV);
    float ssrMask = reflectedColor.w;

    float3 finalColor = lerp(sceneColor.rgb, reflectedColor.rgb, ssrMask);
    finalColor = reflectedColor.rgb;
    
    return float4(finalColor.xyz, 1.0);
}
//#endregion