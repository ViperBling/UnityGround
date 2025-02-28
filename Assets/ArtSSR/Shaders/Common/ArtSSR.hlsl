#pragma once

#include "Assets/ArtSSR/Shaders/Common/SSRCommon.hlsl"

float4 LinearFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;

    half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;
    
    UNITY_BRANCH
    if (isBackground) return half4(screenUV.xy, 0, 1);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, screenUV);
    float smoothness = normalGBuffer.w;
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);

    UNITY_BRANCH
    if (smoothness < _MinSmoothness || isBackground) return half4(screenUV.xy, 0, 1);

    float4 positionNDC = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
    #ifdef UNITY_UV_STARTS_AT_TOP
        positionNDC.y *= -1;
    #endif
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    // 后面会直接用到positionVS，所以要先除以w
    positionVS *= rcp(positionVS.w);
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    float3 reflectDirWS = reflect(viewDirWS, normalWS);
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

    // float3 intersectPoint = LinearTrace(float3 positionVS, float3 reflectDir, float thickness, float numSteps, out float depthDelta, out float hit, out float2 hitUV, out float maskOut);

    UNITY_LOOP
    for (int i = 0; i < fixNumStep; i++)
    {
        curPositionVS += rayDir;

        // 根据当前相机空间坐标计算投影坐标
        float4 curPositionCS = mul(GetViewToHClipMatrix(), float4(curPositionVS, 1.0));
        #ifdef UNITY_UV_STARTS_AT_TOP
            curPositionCS.y *= -1;
        #endif
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
        #ifdef UNITY_UV_STARTS_AT_TOP
            curPositionCS.y *= -1;
        #endif
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

float4 SSTracingFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);

    float2 screenUV = fsIn.texcoord;

    float rawDepth = 1 - SampleDepth(screenUV, 0);

    UNITY_BRANCH
    if (rawDepth == 0) return float4(screenUV, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, screenUV);
    float smoothness = normalGBuffer.w;
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);

    // Temp, return screenUV
    // UNITY_BRANCH
    // if (smoothness < _MinSmoothness) return float4(0, 0, 0, 0);

    float4 positionNDC = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
    #ifdef UNITY_UV_STARTS_AT_TOP
        positionNDC.y *= -1;
    #endif
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    // 后面会直接用到positionVS，所以要先除以w
    positionVS *= rcp(positionVS.w);
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    float3 reflectDirWS = reflect(viewDirWS, normalWS);
    float3 reflectDirVS = normalize(mul(UNITY_MATRIX_V, float4(reflectDirWS, 0.0))).xyz;

    // Project the end point of reflection ray to get screen-space direction
    float3 rayEndVS = positionVS.xyz - reflectDirVS * positionVS.z;
    float4 rayEndCS = mul(UNITY_MATRIX_P, float4(rayEndVS, 1.0));
    rayEndCS /= rayEndCS.w;

    float3 finalResult = rayEndCS;

    return float4(finalResult, 1);
    
    // // Convert to UV space for traversal
    // float2 rayStartUV = screenUV;
    // float2 rayEndUV = rayEndCS.xy * 0.5 + 0.5;
    // #ifdef UNITY_UV_STARTS_AT_TOP
    //     rayEndUV.y = 1.0 - rayEndUV.y;
    // #endif
    
    // // Initialize DDA variables
    // float2 rayDir = rayEndUV - rayStartUV;
    // float rayLength = length(rayDir);
    // rayDir /= rayLength; // Normalize
    
    // // Get depth-based ray step size
    // float depthVS = -positionVS.z; // Convert to positive value for easier comparison
    // float rayStepSize = _StepStride / (_ScreenParams.x * max(abs(rayDir.x), abs(rayDir.y)));
    
    // // Add jitter to reduce banding artifacts
    // // float jitter = IGN(screenUV.x * _ScreenParams.x, screenUV.y * _ScreenParams.y, _FrameCount) * _JitterAmount;
    // float2 currentPos = rayStartUV + rayDir * rayStepSize * 1;
    
    // // Initialize hit detection variables
    // bool hitFound = false;
    // float2 hitPos = rayStartUV;
    // float hitMask = 0;
    
    // // Adaptive ray step size based on reflection direction
    // float VoR = saturate(dot(viewDirWS, reflectDirWS));
    // float adaptiveStepSize = rayStepSize * lerp(1.0, 3.0, VoR * VoR);
    
    // // DDA ray marching loop
    // UNITY_LOOP
    // for (int i = 0; i < _MaxSteps && !hitFound; ++i)
    // {
    //     // March ray
    //     currentPos += rayDir * adaptiveStepSize;
        
    //     // Skip if out of screen bounds
    //     UNITY_BRANCH
    //     if (any(currentPos < 0) || any(currentPos > 1))
    //         break;
            
    //     // Sample depth at current position
    //     float sampledDepth = SampleDepth(currentPos, 0);
        
    //     // Skip background
    //     UNITY_BRANCH
    //     if (sampledDepth == 0)
    //         continue;
        
    //     // Convert to view space for depth comparison
    //     float4 hitPosNDC = float4(currentPos * 2.0 - 1.0, sampledDepth, 1.0);
    //     #ifdef UNITY_UV_STARTS_AT_TOP
    //         hitPosNDC.y *= -1;
    //     #endif
    //     float4 hitPosVS = mul(UNITY_MATRIX_I_P, hitPosNDC);
    //     hitPosVS /= hitPosVS.w;
        
    //     // Get interpolated ray depth at current position
    //     float rayProgress = length(currentPos - rayStartUV) / rayLength;
    //     float rayDepthVS = -lerp(depthVS, rayEndVS.z, rayProgress);
        
    //     // Check for intersection
    //     float depthDiff = rayDepthVS - (-hitPosVS.z);
        
    //     // Hit detection with thickness factor
    //     float thickness = _ThicknessScale * 0.01 * (1.0 + (i / _MaxSteps));
        
    //     UNITY_BRANCH
    //     if (depthDiff >= 0 && depthDiff < thickness)
    //     {
    //         // Binary search refinement for more precise intersection
    //         float2 prevPos = currentPos - rayDir * adaptiveStepSize;
    //         float2 refinedPos = BinarySearchRayHit(prevPos, currentPos, rayDepthVS, thickness);
            
    //         // Get refined hit position
    //         hitPos = refinedPos;
    //         hitFound = true;
            
    //         // Calculate hit quality factors
    //         float edgeFade = ScreenEdgeMask(hitPos);
    //         float distanceFade = 1.0 - saturate(rayProgress * 2.0);
            
    //         // Check backface hit
    //         float3 hitNormal = UnpackNormal(SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, hitPos).xyz);
    //         float backfaceFactor = saturate(-dot(hitNormal, reflectDirWS)) * 2.0; // More weight for proper facing
            
    //         // Calculate final hit mask
    //         hitMask = hitFound * edgeFade * distanceFade * backfaceFactor * smoothness;
    //         break;
    //     }
        
    //     // Adaptive step size increase for rays that travel far
    //     adaptiveStepSize *= 1.05;
    // }

    // float3 finalResult = hitMask;

    // return float4(finalResult, 1);
}

float4 HiZFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);

    float2 screenUV = fsIn.texcoord;

    float rawDepth = 1 - SampleDepth(screenUV, 0);

    UNITY_BRANCH
    if (rawDepth == 0) return float4(screenUV, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, screenUV);
    float smoothness = normalGBuffer.w;
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);

    // Temp, return screenUV
    UNITY_BRANCH
    if (smoothness < _MinSmoothness) return float4(0, 0, 0, 0);

    float4 positionNDC = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
    #ifdef UNITY_UV_STARTS_AT_TOP
        positionNDC.y *= -1;
    #endif
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    // 后面会直接用到positionVS，所以要先除以w
    positionVS *= rcp(positionVS.w);
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    float3 reflectDirWS = reflect(viewDirWS, normalWS);
    float3 reflectDirVS = normalize(mul(UNITY_MATRIX_V, float4(reflectDirWS, 0.0))).xyz;

    // positionVS的z轴为负，所以要取反才能得到正确的反射位置
    float3 reflectionEndPosVS = positionVS.xyz - reflectDirVS * positionVS.z;
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
    float thickness = (1 - camVoR) * 0.01 * _ThicknessScale;

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
    finalColor = reflectedUV.xyz;
    
    return half4(finalColor.xyz, 1.0);
}