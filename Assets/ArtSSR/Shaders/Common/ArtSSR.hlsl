#pragma once

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
    float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepth, fsIn.texCoord).r;

    [branch]
    if (rawDepth == 0) return float4(0, 0, 0, 0);

    float4 normalGBuffer = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_GBuffer, fsIn.texCoord, 0);
    float smoothness = normalGBuffer.w;
    float3 normal = normalGBuffer.xyz * 2.0 - 1.0;

    float4 posCS = float4(fsIn.texCoord * 2.0 - 1.0 , rawDepth, 1.0);
    float4 posVS = mul(_InverseProjectionMatrix, posCS);

    
    return half4(1, 0, 0, 1);
}

float4 HiZFragmentPass(Varyings fsIn) : SV_Target
{
    return half4(0, 1, 0, 1);
}

float4 CompositeFragmentPass(Varyings fsIn) : SV_Target
{
    return half4(0, 0, 1, 1);
}