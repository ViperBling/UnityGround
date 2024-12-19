#pragma once

#include "Assets/ArtSSR/Shaders/Common/SSRCommon.hlsl"
#include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"

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

    float4 normalGBuffer = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_GBuffer, fsIn.texCoord, 0);
    float smoothness = normalGBuffer.w;
    float3 normal = normalGBuffer.xyz * 2.0 - 1.0;

    float4 positionCS = float4(fsIn.texCoord * 2.0 - 1.0 , rawDepth, 1.0);
    float4 positionVS = mul(_InvProjectionMatrix, positionCS);
    positionVS /= positionVS.w;
    positionVS.y *= -1;

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

            if (depthDelta > thickness) hit = 0;

            int binarySearchSteps = BINARY_STEP_COUNT * hit;

            UNITY_LOOP
            for (int i = 0; i < BINARY_STEP_COUNT; i++)
            {
                
            }
        }
    }
    
    return half4(1, 0, 0, 1);
}

float4 HiZFragmentPass(Varyings fsIn) : SV_Target
{
    return half4(1, 1, 0, 1);
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    return half4(1, 1, 1, 1);
}