#pragma once

#include "Assets/ArtSSR/Shaders/Common/SSRCommon.hlsl"

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

    UNITY_BRANCH
    if (smoothness < _MinSmoothness) return half4(0, 0, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    bool valid = false;
    float PDF, jitter;
    float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, smoothness, PDF, jitter, valid);
    float3 reflectDirVS = mul(UNITY_MATRIX_V, float4(reflectDirWS, 0)).xyz;

    // float2 noiseUV = (screenUV + 0) * _ScreenResolution.xy / 1024;
    // float2 random = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_point_clamp, noiseUV).xy;
    // // random.y = lerp(random.y, 0.0, _BRDFBias);
    // float4 H = ImportanceSampleGGX_SSR(random, smoothness);
    // float3x3 tangentToWorld = GetTangentBasis(normalWS);
    // H.xyz = mul(H.xyz, tangentToWorld);
    // // float3x3 localToWorld = GetLocalFrame(normalWS);
    // // H.xyz = mul(H, localToWorld);
    // // reflectDirWS = reflect(viewDirWS, H.xyz);
    // // reflectDirVS = mul(UNITY_MATRIX_V, float4(reflectDirWS, 0)).xyz;

    // return half4(reflectDirVS.xyz, 1);

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

    half3 finalResult = half3(curScreenTexCoord.xy, maskOut);
    
    return half4(finalResult, PDF);
}

float4 LinearSSTracingPass(Varyings fsIn) : SV_Target
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

    UNITY_BRANCH
    if (smoothness < _MinSmoothness) return half4(screenUV.xy, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    bool valid = false;
    float PDF = 1.0;
    float jitter = 0.0;
    float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, smoothness, PDF, jitter, valid);
    float3 reflectDirVS = TransformWorldToViewDir(reflectDirWS);

    float3 startPosVS = positionVS.xyz;
    float3 endPosVS = startPosVS - reflectDirVS * positionVS.z * 10;

    // H0
    float4 startHCS = mul(UNITY_MATRIX_P, float4(startPosVS, 1.0));
    startHCS.xy = (float2(startHCS.x, startHCS.y * _ProjectionParams.x) + startHCS.w) * 0.5;
    startHCS.xy *= _ScreenResolution.xy;

    // H1
    float4 endHCS = mul(UNITY_MATRIX_P, float4(endPosVS, 1.0));
    endHCS.xy = (float2(endHCS.x, endHCS.y * _ProjectionParams.x) + endHCS.w) * 0.5;
    endHCS.xy *= _ScreenResolution.xy;

    float startK = 1.0 / startHCS.w;        // K0
    float endK = 1.0 / endHCS.w;            // K1

    float2 startSS = startHCS.xy * startK;  // P0
    float2 endSS = endHCS.xy * endK;        // P1

    float3 startQ = startPosVS * startK;    // Q0
    float3 endQ = endPosVS * endK;          // Q1

    half xMax = _ScreenResolution.x - 0.5;
    half xMin = 0.5;
    half yMax = _ScreenResolution.y - 0.5;
    half yMin = 0.5;
    half alpha = 0.0;

    // 防止在屏幕边缘时出现拉伸
    if (endSS.x > xMax || endSS.x < xMin)
    {
        half xClip = (endSS.x > xMax) ? xMax : xMin;
        half xAlpha = (endSS.x - xClip) / (endSS.x - startSS.x);
        alpha = xAlpha;
    }
    if (endSS.y > yMax || endSS.y < yMin)
    {
        half yClip = (endSS.y > yMax) ? yMax : yMin;
        half yAlpha = (endSS.y - yClip) / (endSS.y - startSS.y);
        alpha = max(alpha, yAlpha);
    }
    endSS = lerp(endSS, startSS, alpha);
    endK = lerp(endK, startK, alpha);
    endQ = lerp(endQ, startQ, alpha);

    endSS = (DistanceSquared(startSS, endSS) < 0.0001) ? startSS + half2(0.01, 0.01) : endSS;

    float2 deltaSS = endSS - startSS;
    bool permute = false;
    if (abs(deltaSS.x) < abs(deltaSS.y))
    {
        permute = true;
        deltaSS = deltaSS.yx;
        startSS = startSS.yx;
        endSS = endSS.yx;
    }

    half stepDirSS = sign(deltaSS.x);
    half invDX = stepDirSS / deltaSS.x;
    half2 dP = half2(stepDirSS, invDX * deltaSS.y);
    half3 dQ = (endQ - startQ) * invDX;
    half dK = (endK - startK) * invDX;

    half2 P = startSS;
    half3 Q = startQ;
    half K = startK;
    half preZMaxEstimate = positionVS.z;
    half rayZMax = preZMaxEstimate;
    half rayZMin = preZMaxEstimate;
    half end = endSS.x * stepDirSS;

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

    dP *= scaledStepStride;
    dQ *= scaledStepStride;
    dK *= scaledStepStride;

    startSS += dP * jitter;
    startQ += dQ * jitter;
    startK += dK * jitter;

    float stepTaked = 0;
    float2 hitUV = screenUV;
    half hit = 0;

    UNITY_LOOP
    for (int i = 0; i < fixNumStep && (P.x * stepDirSS) <= end; i++)
    {
        rayZMin = preZMaxEstimate;
        rayZMax = (dQ.z * 0.5 + Q.z) / (dK * 0.5 + K);
        preZMaxEstimate = rayZMax;

        if (rayZMin > rayZMax)
        {
            half temp = rayZMin;
            rayZMin = rayZMax;
            rayZMax = temp;
        }

        hitUV = permute ? P.yx : P;
        float2 sampelUV = hitUV / _ScreenResolution.xy;
        float sampledDepth = SampleDepth(sampelUV);
        float surfaceDepth = -LinearEyeDepth(sampledDepth, _ZBufferParams);

        bool isBehind = rayZMin + 0.1 <= surfaceDepth;

        hit = isBehind && (rayZMax >= surfaceDepth - thickness);
        if (hit) break;
        
        stepTaked++;
        P += dP;
        Q.z += dQ.z;
        K += dK;
    }
    P -= dP;
    Q.z -= dQ.z;
    K -= dK;

    Q.xy += dQ.xy * stepTaked;
    float3 hitPoint = Q * (1 / K);

    hitUV /= _ScreenResolution.xy;

    half maskOut = 0;

    UNITY_BRANCH
    if (hit)
    {
        maskOut = pow(1 - max(2 * stepTaked / fixNumStep - 1, 0), 2);
        maskOut *= saturate(512 - dot(hitPoint - positionVS.xyz, reflectDirVS));

        float3 tNormal = UnpackNormal(SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, hitUV).xyz);
        float backFaceDot = dot(tNormal, reflectDirWS);
        maskOut = backFaceDot > 0 ? 0 : maskOut;
    }

    maskOut *= ScreenEdgeMask(hitUV);

    float3 finalResult = float3(hitUV, maskOut);
    return float4(finalResult, PDF);
}

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

    UNITY_BRANCH
    if (smoothness < _MinSmoothness || isBackground) return half4(screenUV.xy, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    bool valid = false;
    float PDF, jitter;
    float3 reflectDirWS = GetReflectDirWS(screenUV, normalWS, viewDirWS, smoothness, PDF, jitter, valid);
    float3 reflectDirVS = TransformWorldToViewDir(reflectDirWS);

    // positionVS的z轴为负，所以要取反才能得到正确的反射位置
    float3 reflectionEndPosVS = positionVS.xyz - reflectDirVS * positionVS.z * 10;
    float4 reflectionEndPosCS = mul(UNITY_MATRIX_P, float4(reflectionEndPosVS, 1.0));
    reflectionEndPosCS *= rcp(reflectionEndPosCS.w);
    reflectionEndPosCS.z = 1 - reflectionEndPosCS.z;
    positionNDC.z = 1 - positionNDC.z;
    
    // TextureSpace下的反射方向
    float3 outReflectionDirSS = normalize(reflectionEndPosCS - positionNDC).xyz;
    // 缩放向量到[0, 1]范围
    outReflectionDirSS.xy *= float2(0.5, -0.5);

    // TS下的采样位置
    float3 outSamplePosSS = float3(screenUV, positionNDC.z);

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

    float hit = 0;
    float mask = smoothstep(0, 0.1f, camVoR);

    UNITY_BRANCH
    if (mask == 0) return float4(screenUV, 0, 0);

    float iterations;
    bool isSky;
    float3 intersectPoint = HizTrace(thickness, outSamplePosSS, outReflectionDirSS, _MaxSteps, hit, iterations, isSky);

    float edgeMask = ScreenEdgeMask(intersectPoint.xy);

    float3 tNormal = UnpackNormal(SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, intersectPoint.xy).xyz);
    float backFaceDot = dot(tNormal, reflectDirWS);
    mask = backFaceDot > 0 && !isSky ? 0 : mask;

    mask *= hit * edgeMask;

    // float smoothnessPow4 = Pow4(smoothness);
    // float stepS = smoothstep(_MinSmoothness, 1, smoothness);
    // float fresnel = lerp(smoothnessPow4, 1.0, pow(VoR, 1.0 / smoothnessPow4));
    // float alpha = stepS;

    float3 finalResult = float3(intersectPoint.xy, mask);

    return half4(finalResult, PDF);
}

float4 SpatioFilterPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;

    // float rawDepth = SampleDepth(screenUV);

    // half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    // bool isBackground = rawDepth == 0.0;

    // float smoothness;
    // float3 normalWS = GetNormalWS(screenUV, smoothness);
    // float3 normalVS = TransformWorldToViewNormal(normalWS);

    // UNITY_BRANCH
    // if (smoothness < _MinSmoothness || isBackground) return 0.0;

    // float4 positionNDC, positionVS;
    // float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    // // float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);

    // // float2 noiseUV = (screenUV + _SSRJitter.zw) * _ScreenResolution.xy / 1024;
    // // float2 blueNoise = SAMPLE_TEXTURE2D(_BlueNoiseTexture, sampler_BlueNoiseTexture, noiseUV) * 2.0 - 1.0;
    // // float2x2 offsetRotationMatrix = float2x2(blueNoise.x, blueNoise.y, -blueNoise.y, -blueNoise.x);

    // float2 random = float2(GenerateRandomFloat(screenUV, _ScreenResolution.xy, _RandomSeed), GenerateRandomFloat(screenUV, _ScreenResolution.xy, _RandomSeed));
    // float2x2 offsetRotationMatrix = float2x2(cos(random.x), sin(random.y), -sin(random.x), cos(random.y));

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

    //     float4 hitUV = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, neighborUV);

    //     float sampledDepth = SampleDepth(hitUV.xy);
    //     float4 hitPosNDC, hitPosVS;
    //     float4 hitPosWS = ReconstructPositionWS(hitUV.xy, sampledDepth, hitPosNDC, hitPosVS);

    //     float PDF = 1.0;
    //     weight = SSRBRDF(normalize(-positionVS.xyz), normalize(hitPosVS - positionVS).xyz, normalVS, smoothness, PDF);
    //     weight /= max(1e-5, PDF);
    //     // weight = 50;
    //     sampleColor = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, hitUV.xy);
    //     sampleColor.rgb /= 1 + Luminance(sampleColor.rgb);
    //     sampleColor.a = hitUV.z;

    //     reflectionColor += sampleColor * weight;
    //     numWeight += weight;
    // }

    // reflectionColor /= numWeight;
    // reflectionColor.rgb /= 1 - Luminance(reflectionColor.rgb);
    // reflectionColor.rgb = max(reflectionColor.rgb, 1e-5);
    // reflectionColor.a = sampleColor.a;

    // return reflectionColor;

    float4 hitUV = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV);
    // float4 reflectionColor = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_SSRSceneColorTexture, hitUV.xy);
    return hitUV;

    // float3 finalResult = normalVS;
    // return float4(finalResult, 1.0);
}

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

    colorMin = mean - 1.25 * stdDev;
    colorMax = mean + 1.25 * stdDev;

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

    float temporalBlendWeight = saturate(1 - length(velocity) * 8 * 0.9);
    float4 reflectionColor = lerp(ssrCurColor, prevColor, temporalBlendWeight);

    float4 curColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV);
    float3 result = curColor.xyz;
    // return float4(result, 1.0);
    return reflectionColor;
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;
    half4 sceneColor = SAMPLE_TEXTURE2D(_SSRSceneColorTexture, sampler_point_clamp, screenUV);

    UNITY_BRANCH
    if (rawDepth == 0.0) return sceneColor;

    half3 albedo;
    half3 specular;
    half occlusion;
    half3 normal;
    half smoothness;
    HitDataFromGBuffer(screenUV, albedo, specular, occlusion, normal, smoothness);
    
    float4 reflectedUV = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, screenUV);

    // half3 reflectedColor = SAMPLE_TEXTURE2D_LOD(_SSRSceneColorTexture, sampler_point_clamp, reflectedUV.xy, 0.0).rgb;
    half3 reflectedColor = reflectedUV.xyz;

    reflectedColor *= occlusion;
    half reflectivity = ReflectivitySpecular(specular);

    half fresnel = (max(smoothness, 0.04) - 0.04) * Pow4(1.0 - saturate(dot(normal, _WorldSpaceViewDir))) + 0.04;
    reflectedColor = lerp(reflectedColor, reflectedColor * specular, saturate(reflectivity - fresnel));
    
    half3 finalColor = lerp(sceneColor.xyz, reflectedColor.xyz, saturate(reflectivity + fresnel) * reflectedUV.w);
    finalColor = reflectedUV.xyz;
    
    return half4(finalColor.xyz, 1.0);
}