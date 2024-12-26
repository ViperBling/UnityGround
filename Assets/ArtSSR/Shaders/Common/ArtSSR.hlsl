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
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, point_clamp_sampler, fsIn.texCoord).r;

    [branch]
    if (rawDepth == 0) return float4(0, 0, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, fsIn.texCoord);
    float smoothness = normalGBuffer.w;
    float3 normal = UnpackNormal(normalGBuffer.xyz);

    float4 positionCS = float4(fsIn.texCoord * 2.0 - 1.0 , rawDepth, 1.0);
    float4 positionVS = mul(_InvProjectionMatrix, positionCS);
    positionVS /= positionVS.w;
    // UNITY_UV_STARTS_AT_TOP
    positionVS.y *= -1;
    // 重建世界坐标
    float4 positionWS = mul(_InvViewMatrix, positionVS);
    float3 viewDirWS = normalize(float3(positionWS.xyz) - _WorldSpaceCameraPos);
    // 视线的反射向量
    float3 reflectDirWS = reflect(viewDirWS, normal);
    
    float3 reflectDirVS = mul(_ViewMatrix, float4(reflectDirWS, 0)).xyz;
    reflectDirVS.z *= -1;
    positionVS.z *= -1;

    float VoR = saturate(dot(viewDirWS, reflectDirWS));
    float camVoR = saturate(dot(_WorldSpaceViewDir, reflectDirWS));

    float thickness = _StepStride * 2;
    float oneMinusVoR = sqrt(1 - VoR);
    _StepStride /= oneMinusVoR;
    thickness /= oneMinusVoR;

    int hit = 0;
    float maskOut = 1;
    float3 currentPositionVS = positionVS.xyz;
    float2 currentPositionSS = fsIn.texCoord;

    bool doRayMarch = smoothness > _MinSmoothness;

    float maxRayLength = _NumSteps * _StepStride;
    float maxDist = lerp(min(positionVS.z, maxRayLength), maxRayLength, camVoR);
    float fixNumStep = max(maxDist / _StepStride, 0);

    UNITY_BRANCH
    if (doRayMarch)
    {
        float3 ray = reflectDirVS * _StepStride;
        float depthDelta = 0;

        UNITY_LOOP
        for (int step = 0; step < fixNumStep; step++)
        {
            currentPositionVS += ray;

            float curDepth;
            float2 curScreenSpace;

            float4 texCoord = mul(_ProjectionMatrix, float4(currentPositionVS.x, -currentPositionVS.y, -currentPositionVS.z, 1));
            texCoord /= texCoord.w;
            texCoord.x = texCoord.x * 0.5 + 0.5;
            texCoord.y = texCoord.y * -0.5 + 0.5;

            UNITY_BRANCH
            if (texCoord.x < 0 || texCoord.x >= 1 || texCoord.y < 0 || texCoord.y >= 1) break;

            float sampledDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, point_clamp_sampler, texCoord.xy).r;

            UNITY_BRANCH
            if (abs(rawDepth - sampledDepth) > 0 && sampledDepth != 0)
            {
                depthDelta = currentPositionVS.z - LinearEyeDepth(sampledDepth, _ProjectionParams.z);

                UNITY_BRANCH
                if (depthDelta > 0 && depthDelta < _StepStride * 2)
                {
                    currentPositionSS = texCoord.xy;
                    hit = 1;
                    break;
                }
            }
        }

        if (depthDelta > thickness) hit = 0;

        int binarySearchSteps = BINARY_STEP_COUNT * hit;

        UNITY_LOOP
        for (int i = 0; i < BINARY_STEP_COUNT; i++)
        {
            ray *= 0.5f;
                
            UNITY_FLATTEN
            if (depthDelta > 0)
            {
                currentPositionVS -= ray;
            }
            else if (depthDelta < 0)
            {
                currentPositionVS += ray;
            }
            else
            {
                break;
            }

            float4 texCoord = mul(_ProjectionMatrix, float4(currentPositionVS.x, -currentPositionVS.y, -currentPositionVS.z, 1));
            texCoord /= texCoord.w;
            maskOut = ScreenEdgeMask(texCoord);
            texCoord.x = texCoord.x * 0.5 + 0.5;
            texCoord.y = texCoord.y * -0.5 + 0.5;

            currentPositionSS = texCoord.xy;

            float sd = SAMPLE_TEXTURE2D(_CameraDepthTexture, point_clamp_sampler, texCoord.xy).r;
            depthDelta = currentPositionVS.z - LinearEyeDepth(sd, _ProjectionParams.z);
            float minV = 1.0 / max(oneMinusVoR * float(i), 0.001);
            if (abs(depthDelta) > minV)
            {
                hit = 0;
                break;
            }
        }

        // Remove backface intersections
        float3 currentNormal = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_point_clamp, currentPositionSS, 0);
        float3 curUnpackNormal = currentNormal * 2.0 - 1.0;
        float backFaceDot = dot(curUnpackNormal, reflectDirWS);

        UNITY_FLATTEN
        if (backFaceDot > 0) hit = 0;
    }

    float3 deltaDir = positionVS.xyz - currentPositionVS;
    float progress = dot(deltaDir, deltaDir) / (maxDist * maxDist);
    progress = smoothstep(0.0, 0.5, 1 - progress);

    maskOut *= hit;
    
    half3 finalResult = half3(currentPositionSS, maskOut * progress);
    // finalResult = normal;
    
    return half4(finalResult, 1);
}

float4 HiZFragmentPass(Varyings fsIn) : SV_Target
{
    return half4(1, 1, 0, 1);
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    half invPaddedScale = 1.0 / _PaddedScale;
    float4 sceneColor = SAMPLE_TEXTURE2D(_TempPaddedSceneColor, sampler_TempPaddedSceneColor, fsIn.texCoord * invPaddedScale);
    
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, point_clamp_sampler, fsIn.texCoord).r;

    UNITY_BRANCH
    if (rawDepth == 0) return half4(0, 0, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D(_GBuffer2, sampler_point_clamp, fsIn.texCoord);
    float3 normalWS = UnpackNormal(normalGBuffer.xyz);
    float steppedSmoothness = smoothstep(_MinSmoothness, 1, normalGBuffer.w);

    float3 positionWS = GetWorldPosition(rawDepth, fsIn.texCoord);
    float3 viewDirWS = normalize(positionWS - _WorldSpaceCameraPos.xyz);

    float fresnel = 1 - dot(viewDirWS, -normalWS);
    normalWS = mul(_ViewMatrix, float4(normalWS, 0)).xyz;
    normalWS.y *= -1;

    float3 reflectedUV = SAMPLE_TEXTURE2D(_ReflectedColorMap, sampler_point_clamp, fsIn.texCoord * invPaddedScale).rgb;
    float maskValue = saturate(reflectedUV.z) * steppedSmoothness;
    // reflectedUV.xy +=

    float lumin = 1.0;
    float luminMask = 1 - lumin;
    luminMask = pow(luminMask, 5);

    half4 reflectedColor = SAMPLE_TEXTURE2D_LOD(_TempPaddedSceneColor, sampler_TempPaddedSceneColor, reflectedUV.xy, 0);

    half4 blendedColor = reflectedColor;

    half3 finalColor = lerp(sceneColor, blendedColor.xyz, 0.5);
    
    return half4(blendedColor.xyz, 1);
}