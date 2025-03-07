#pragma once

#include "Assets/CommonResource/Shaders/Common/Sampling.hlsl"
#include "Assets/ArtSSR/Shaders/Common/SSRCommon.hlsl"

float4 LinearVSTracingPass(Varyings fsIn) : SV_Target
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
    
    float2 randomUV = float2(GenerateRandomFloat(screenUV), GenerateRandomFloat(screenUV));
    bool valid = false;
    float3 reflectDirWS = ImportanceSampleGGX(randomUV, normalWS, viewDirWS, smoothness, valid);
    // float3 reflectDirWS = reflect(viewDirWS, normalWS);
    float3 reflectDirVS = normalize(mul(UNITY_MATRIX_V, float4(reflectDirWS, 0.0))).xyz;

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
    
    return half4(finalResult, 1);
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
    if (smoothness < _MinSmoothness || isBackground) return half4(screenUV.xy, 0, 1);

    float4 positionNDC, positionVS;
    float4 positionWS = ReconstructPositionWS(screenUV, rawDepth, positionNDC, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    float3 reflectDirWS = reflect(viewDirWS, normalWS);
    float3 reflectDirVS = normalize(mul(UNITY_MATRIX_V, float4(reflectDirWS, 0.0))).xyz;

    float3 startPosVS = positionVS.xyz;
    float3 endPosVS = startPosVS - reflectDirVS * positionVS.z * 10;

    // H0
    float4 startHCS = mul(UNITY_MATRIX_P, float4(startPosVS, 1.0));
    startHCS.xy = (float2(startHCS.x, startHCS.y * _ProjectionParams.x) + startHCS.w) * 0.5;
    startHCS.xy *= _ScreenResolution;

    // H1
    float4 endHCS = mul(UNITY_MATRIX_P, float4(endPosVS, 1.0));
    endHCS.xy = (float2(endHCS.x, endHCS.y * _ProjectionParams.x) + endHCS.w) * 0.5;
    endHCS.xy *= _ScreenResolution;

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
        float2 sampelUV = hitUV / _ScreenResolution;
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
    // P -= dP;
    // Q.z -= dQ.z;
    // K -= dK;

    // Q.xy += dQ.xy * stepTaked;
    hitUV /= _ScreenResolution;

    half maskOut = ScreenEdgeMask(hitUV);
    maskOut *= hit;

    half3 finalResult = half3(hitUV, maskOut);
    return half4(finalResult, 1);
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
    float3 reflectDirWS = reflect(viewDirWS, normalWS);
    float3 reflectDirVS = normalize(mul(UNITY_MATRIX_V, float4(reflectDirWS, 0.0))).xyz;

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

    float smoothnessPow4 = Pow4(smoothness);
    float stepS = smoothstep(_MinSmoothness, 1, smoothness);
    float fresnel = lerp(smoothnessPow4, 1.0, pow(VoR, 1.0 / smoothnessPow4));

    half3 finalResult = half3(intersectPoint.xy, mask);
    half alpha = stepS;

    return half4(finalResult, alpha);
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

    half fresnel = (max(smoothness, 0.04) - 0.04) * Pow4(1.0 - saturate(dot(normal, _WorldSpaceViewDir))) + 0.04;

    half3 reflectedColor = SAMPLE_TEXTURE2D_LOD(_SSRSceneColorTexture, sampler_point_clamp, reflectedUV.xy, 0.0).rgb;

    reflectedColor *= occlusion;
    half reflectivity = ReflectivitySpecular(specular);

    reflectedColor = lerp(reflectedColor, reflectedColor * specular, saturate(reflectivity - fresnel));
    
    half3 finalColor = lerp(sceneColor.xyz, reflectedColor.xyz, saturate(reflectivity + fresnel) * reflectedUV.z);
    // finalColor = reflectedUV.xyz;
    
    return half4(finalColor.xyz, 1.0);
}