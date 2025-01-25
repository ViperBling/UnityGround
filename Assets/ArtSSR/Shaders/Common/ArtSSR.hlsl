#pragma once

#include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
#include "Assets/ArtSSR/Shaders/Common/SSRCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float2 texCoord : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 texCoord : TEXCOORD0;
};


Varyings VertexPass(Attributes vsIn)
{
    Varyings vsOut = (Varyings)0;

    vsOut.positionCS = TransformObjectToHClip(vsIn.positionOS.xyz);
    vsOut.texCoord = vsIn.texCoord;

    return vsOut;
}

float4 LinearFragmentPass(Varyings fsIn) : SV_Target
{
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_point_clamp, fsIn.texCoord).r;
    
    [branch]
    if (rawDepth == 0) return float4(0, 0, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, fsIn.texCoord);
    float smoothness = normalGBuffer.w;
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);

    float4 positionNDC = float4(fsIn.texCoord * 2.0 - 1.0 , rawDepth, 1.0);
#if UNITY_UV_STARTS_AT_TOP
    positionNDC.y *= -1;
#endif
    float4 positionVS = mul(_InvProjectionMatrixSSR, positionNDC);
    // 后面会直接用到positionVS，所以要先除以w
    positionVS /= positionVS.w;
    float4 positionWS = mul(_InvViewMatrixSSR, positionVS);

    float3 viewDirWS = normalize(positionWS.xyz - _WorldSpaceCameraPos);
    float3 reflectDirWS = reflect(viewDirWS, normalWS);
    float3 reflectDirVS = normalize(mul(_ViewMatrixSSR, float4(reflectDirWS, 0.0))).xyz;

    float3 curPositionVS = positionVS.xyz;
    float2 curScreenTexCoord = fsIn.texCoord;

    int hit = 0;
    bool doRayMarch = smoothness > _MinSmoothness;

    UNITY_BRANCH
    if (doRayMarch)
    {
        // 步进方向
        float3 rayDir = reflectDirVS * _StepStride;

        UNITY_LOOP
        for (int i = 0; i < _NumSteps; i++)
        {
            curPositionVS += rayDir;

            // 根据当前相机空间坐标计算投影坐标
            float4 curPositionCS = mul(_ProjectionMatrixSSR, float4(curPositionVS, 1.0));
        #if UNITY_UV_STARTS_AT_TOP
            curPositionCS.y *= -1;
        #endif
            // 除以w得到归一化设备坐标
            float3 texCoord = curPositionCS.xyz / curPositionCS.w;
            texCoord.x = texCoord.x * 0.5 + 0.5;
            texCoord.y = texCoord.y * 0.5 + 0.5;

            UNITY_BRANCH
            if (texCoord.x < 0 || texCoord.x > 1 || texCoord.y < 0 || texCoord.y > 1) break;

            // 当前步进位置的深度
            float sampledDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_point_clamp, texCoord.xy).r;

            UNITY_BRANCH
            if (abs(sampledDepth - rawDepth) > 0.0 && sampledDepth != 0)
            {
                // 当前步进位置的线性深度
                float linearDepth = LinearEyeDepth(sampledDepth, _ZBufferParams);
                // 真实深度值和采样深度值的差值
                float depthDelta = -curPositionVS.z - linearDepth;
                
                UNITY_BRANCH
                if (depthDelta > 0 && depthDelta < _StepStride * 2.0)
                {
                    hit = 1;
                    curScreenTexCoord = texCoord.xy;
                    break;
                }
            }
        }
    }
    
    half3 finalResult = half3(curScreenTexCoord, hit);
    
    return half4(finalResult, 1);
    
//     float4 positionCS = float4(fsIn.texCoord * 2.0 - 1.0 , rawDepth, 1.0);
//     float4 positionVS = mul(_InvProjectionMatrixSSR, positionCS);
//     positionVS /= positionVS.w;
// #if UNITY_UV_STARTS_AT_TOP
//     positionVS.y *= -1;
// #endif
//     // 重建世界坐标
//     float4 positionWS = mul(_InvViewMatrixSSR, positionVS);
//     float3 viewDirWS = normalize(float3(positionWS.xyz) - _WorldSpaceCameraPos);
//     // 视线的反射向量
//     float3 reflectDirWS = reflect(viewDirWS, normal);
//     
//     float3 reflectDirVS = normalize(mul(_ViewMatrixSSR, float4(reflectDirWS, 0))).xyz;
//     reflectDirVS.z *= -1;
//     positionVS.z *= -1;
//
//     float VoR = saturate(dot(viewDirWS, reflectDirWS));
//     float camVoR = saturate(dot(_WorldSpaceViewDir, reflectDirWS));
//
//     // 越界检测，超过thickness认为在物体内部
//     float thickness = _StepStride * 2;
//     float oneMinusVoR = sqrt(1 - VoR);
//     float scaledStepStride = _StepStride / oneMinusVoR;
//     thickness /= oneMinusVoR;
//     
//     int hit = 0;
//     float maskOut = 1;
//     float3 currentPositionVS = positionVS.xyz;
//     float2 currentPositionSS = fsIn.texCoord;
//     float3 currentPositionWS = positionWS.xyz;
//     
//     bool doRayMarch = smoothness > _MinSmoothness;
//
//     // 步长调整
//     float maxRayLength = _NumSteps * scaledStepStride;
//     float maxDist = lerp(min(positionVS.z, maxRayLength), maxRayLength, camVoR);
//     float fixNumStep = max(maxDist / scaledStepStride, 0);
    
    // UNITY_BRANCH
    // if (doRayMarch)
    // {
    //     float3 ray = reflectDirVS * scaledStepStride;
    //     float depthDelta = 0;
    //
    //     UNITY_LOOP
    //     for (int step = 0; step < fixNumStep; step++)
    //     {
    //         currentPositionVS += ray;
    //
    //         float4 texCoord = mul(_ProjectionMatrix, float4(currentPositionVS.x, -currentPositionVS.y, -currentPositionVS.z, 1.0));
    //         texCoord /= texCoord.w;
    //         texCoord.x = texCoord.x * 0.5 + 0.5;
    //         texCoord.y = texCoord.y * 0.5 + 0.5;
    //
    //         UNITY_BRANCH
    //         if (texCoord.x < 0 || texCoord.x > 1 || texCoord.y < 0 || texCoord.y > 1) break;
    //
    //         float sampledDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, point_clamp_sampler, texCoord.xy).r;
    //
    //         UNITY_BRANCH
    //         if (abs(rawDepth - sampledDepth) > 0 && sampledDepth != 0)
    //         {
    //             depthDelta = currentPositionVS.z - LinearEyeDepth(sampledDepth, _ZBufferParams.z);
    //
    //             UNITY_BRANCH
    //             if (depthDelta > 0 && depthDelta < scaledStepStride * 2.0)
    //             {
    //                 currentPositionSS = texCoord.xy;
    //                 hit = 1;
    //                 break;
    //             }
    //         }
    //     }
    //
    //     UNITY_FLATTEN
    //     if (depthDelta > thickness) hit = 0;
    //     
    //     UNITY_LOOP
    //     for (int i = 0; i < BINARY_STEP_COUNT; i++)
    //     {
    //         ray *= 0.5f;
    //
    //         UNITY_FLATTEN
    //         if (depthDelta > 0)
    //         {
    //             currentPositionVS -= ray;
    //         }
    //         else if (depthDelta < 0)
    //         {
    //             currentPositionVS += ray;
    //         }
    //         else
    //         {
    //             break;
    //         }
    //     
    //         float4 texCoord = mul(_ProjectionMatrix, float4(currentPositionVS.x, -currentPositionVS.y, -currentPositionVS.z, 1));
    //         texCoord /= texCoord.w;
    //         maskOut = ScreenEdgeMask(texCoord);
    //         texCoord.x = texCoord.x * 0.5 + 0.5;
    //         texCoord.y = texCoord.y * 0.5 + 0.5;
    //
    //         currentPositionSS = texCoord.xy;
    //
    //         float sampledDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, point_clamp_sampler, texCoord.xy).r;
    //         depthDelta = currentPositionVS.z - LinearEyeDepth(sampledDepth, _ZBufferParams.z);
    //         float minV = 1.0 / max(oneMinusVoR * float(i), 0.001);
    //         if (abs(depthDelta) > minV)
    //         {
    //             hit = 0;
    //             break;
    //         }
    //     }
    //     
    //     // Remove backface intersections
    //     float3 currentNormal = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, currentPositionSS);
    //     float3 curUnpackNormal = UnpackNormal(currentNormal);
    //     float backFaceDot = dot(curUnpackNormal, reflectDirWS);
    //     
    //     UNITY_FLATTEN
    //     if (backFaceDot > 0) hit = 0;
    // }
    //
    // float3 deltaDir = positionVS.xyz - currentPositionVS;
    // float progress = dot(deltaDir, deltaDir) / (maxDist * maxDist);
    // progress = smoothstep(0.0, 0.5, 1 - progress);
    //
    // maskOut *= hit;
    
    // half3 finalResult = half3(currentPositionSS, maskOut);
    // half3 finalResult = positionCS;
    //
    // return half4(finalResult, 1);
}

float4 HiZFragmentPass(Varyings fsIn) : SV_Target
{
    return half4(1, 1, 0, 1);
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    half invPaddedScale = 1.0 / _PaddedScale;
    float4 sceneColor = SAMPLE_TEXTURE2D(_TempPaddedSceneColor, sampler_TempPaddedSceneColor, fsIn.texCoord * invPaddedScale);
    
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, fsIn.texCoord).r;

    // Keep Skybox Color
    UNITY_BRANCH
    if (rawDepth == 0) return sceneColor;

    float3 reflectedUV = SAMPLE_TEXTURE2D(_ReflectedColorMap, sampler_point_clamp, fsIn.texCoord * invPaddedScale).rgb;

    half4 reflectedColor = SAMPLE_TEXTURE2D_LOD(_TempPaddedSceneColor, sampler_TempPaddedSceneColor, reflectedUV.xy, 0);

    half4 blendedColor = reflectedColor;

    half3 finalColor = lerp(sceneColor.xyz, blendedColor.xyz, reflectedUV.z);
    
    return half4(finalColor.xyz, 1);
}