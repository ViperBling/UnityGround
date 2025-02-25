#pragma once

#include "Assets/ArtSSR/Shaders/Common/SSRCommon.hlsl"

float4 LinearFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;

    half4 sceneColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_BlitTexture, screenUV, 0);
    bool isBackground = rawDepth == 0.0;
    
    // UNITY_BRANCH
    // if (isBackground) return half4(screenUV.xy, 0, 1);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, screenUV);
    float smoothness = normalGBuffer.w;
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);

    UNITY_BRANCH
    if (smoothness < _MinSmoothness || isBackground) return half4(screenUV.xy, 0, 1);

    float4 positionNDC = float4(screenUV * 2.0 - 1.0 , rawDepth, 1.0);
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

float4 HiZFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);

    float2 paddedScreenUV = fsIn.texcoord * _PaddedScale;

    UNITY_BRANCH
    if (paddedScreenUV.x > 1.0f || paddedScreenUV.y > 1.0f) return float4(0, 0, 0, 0);

    float rawDepth = 1 - SampleDepth(fsIn.texcoord, 0);
    // rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, fsIn.texcoord).r;

    return float4(rawDepth.xxx, 1);

    float2 screenUV = paddedScreenUV;

    UNITY_BRANCH
    if (rawDepth == 0) return float4(0, 0, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, screenUV);
    float smoothness = normalGBuffer.w;
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);

    // UNITY_BRANCH
    // if (smoothness < _MinSmoothness) return float4(0, 0, 0, 0);

    float4 positionNDC = float4(fsIn.texcoord * 2.0 - 1.0 , rawDepth, 1.0);
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


    half3 finalResult = rawDepth;

    return half4(finalResult, 1);
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(fsIn);
    float2 screenUV = fsIn.texcoord;
    
    half2 invPaddedScale = 1.0 / _PaddedScale;
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;
    half4 sceneColor = SAMPLE_TEXTURE2D(_SSRTempSceneColorTexture, sampler_point_clamp, screenUV * invPaddedScale);

    UNITY_BRANCH
    if (rawDepth == 0.0) return sceneColor;

    half3 albedo;
    half3 specular;
    half occlusion;
    half3 normal;
    half smoothness;
    HitDataFromGBuffer(screenUV, albedo, specular, occlusion, normal, smoothness);
    
    float3 reflectedUV = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, (screenUV) * invPaddedScale).rgb;

    half fresnel = (max(smoothness, 0.04) - 0.04) * Pow4(1.0 - saturate(dot(normal, _WorldSpaceViewDir))) + 0.04;

    half3 reflectedColor = SAMPLE_TEXTURE2D(_SSRTempSceneColorTexture, sampler_point_clamp, reflectedUV.xy).rgb;

    reflectedColor *= occlusion;
    half reflectivity = ReflectivitySpecular(specular);

    reflectedColor = lerp(reflectedColor, reflectedColor * specular, saturate(reflectivity - fresnel));
    
    half3 finalColor = lerp(sceneColor.xyz, reflectedColor.xyz, saturate(reflectivity + fresnel) * reflectedUV.z);
    // finalColor = reflectedUV.xyz;
    
    return half4(finalColor.xyz, 1.0);
}