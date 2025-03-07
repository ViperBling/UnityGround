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

float4 ImportanceSampleGGX(float2 random, float smoothness)
{
    float roughness = 1.0 - smoothness;
    float m2 = roughness * roughness;
    float m4 = m2 * m2;

    float phi = 2.0 * PI * random.x;
    float cosTheta = sqrt((1.0 - random.y) / (1.0 + (m4 - 1.0) * random.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    float3 H = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    float d = (cosTheta * m4 - cosTheta) * cosTheta + 1.0;
    float D = m4 / (PI * d * d);
    float PDF = D * cosTheta;

    return float4(H, PDF);
}