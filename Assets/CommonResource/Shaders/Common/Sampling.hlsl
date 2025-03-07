#pragma once

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

float3 ImportanceSampleGGX(float2 random, float3 normalWS, float3 viewDirWS, float smoothness, out bool valid)
{
    float roughness = 1.0 - smoothness;
    float alpha2 = roughness * roughness;
    float alpha4 = alpha2 * alpha2;

    half3x3 locaToWorld = GetLocalFrame(normalWS);
    float VoH;
    float3 localV, localH;
    // SampleGGXVisibleNormal(random, -viewDirWS, locaToWorld, alpha2, localV, localH, VoH);
    SampleAnisoGGXVisibleNormal(random, -viewDirWS, locaToWorld, alpha4, alpha2, localV, localH, VoH);

    float3 localL = 2.0 * VoH * localH - localV;
    float3 outDirWS = mul(localL, locaToWorld);
    float NoL = dot(normalWS, outDirWS);

    valid = (NoL >= 0.0001);

    return outDirWS;
}