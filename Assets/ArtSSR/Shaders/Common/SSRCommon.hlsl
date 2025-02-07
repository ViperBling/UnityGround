#pragma once

#define BINARY_STEP_COUNT 32

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness

TEXTURE2D_X(_SSRCameraBackFaceDepthTexture);

SAMPLER(sampler_BlitTexture);
SAMPLER(sampler_point_clamp);

CBUFFER_START(UnityPerMaterial)
    float3      _WorldSpaceViewDir;
    half        _ThicknessScale;
    half        _EdgeFade;
    float       _StepStride;
    float       _MaxSteps;
    float       _MinSmoothness;
    half        _FadeSmoothness;
    int         _Frame;
CBUFFER_END

#ifdef _GBUFFER_NORMALS_OCT
half3 UnpackNormal(half3 pn)
{
    half2 remappedOctNormalWS = half2(Unpack888ToFloat2(pn));           // values between [ 0, +1]
    half2 octNormalWS = remappedOctNormalWS.xy * half(2.0) - half(1.0); // values between [-1, +1]
    return half3(UnpackNormalOctQuadEncode(octNormalWS));               // values between [-1, +1]
}
#else
half3 UnpackNormal(half3 pn) { return pn; }                             // values between [-1, +1]
#endif

// float3 GetWorldPosition(float rawDepth, float2 texCoord)
// {
//     float4 positionNDC = float4(texCoord * 2.0 - 1.0 , rawDepth, 1.0);
// #ifdef UNITY_UV_STARTS_AT_TOP
//     positionNDC.y *= -1;
// #endif
//     float4 positionVS = mul(_InvProjectionMatrixSSR, positionNDC);
//     positionVS /= positionVS.w;
//     float4 positionWS = mul(_InvViewMatrixSSR, positionVS);
//
//     return positionWS.xyz;
// }

inline float ScreenEdgeMask(float2 screenUV)
{
    // float yDiff = 1 - abs(screenUV.y);
    // float xDiff = 1 - abs(screenUV.x);
    //
    // UNITY_FLATTEN
    // if (yDiff < 0 || xDiff < 0)
    // {
    //     return 0;
    // }
    //
    // float t1 = smoothstep(0, 0.2, yDiff);
    // float t2 = smoothstep(0, 0.1, xDiff);
    //
    // return saturate(t1 * t2);
    UNITY_BRANCH
    if (_EdgeFade == 0.0)
    {
        return 1.0;
    }
    else
    {
        half fadeRcpLength = rcp(_EdgeFade);
        float2 coordCS = screenUV * 2.0 - 1.0;
        float2 t = Remap10(abs(coordCS.xy), fadeRcpLength, fadeRcpLength);
        return Smoothstep01(t.x) * Smoothstep01(t.y);
    }
}

inline float RGB2Lum(float3 rgb)
{
    return (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b);
}



