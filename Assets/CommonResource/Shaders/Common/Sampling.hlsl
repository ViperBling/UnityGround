#pragma once

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

#define BICUBIC_CATMULL_ROM_SAMPLES 5

struct FCatmullRomSamples
{
    // Constant number of samples (BICUBIC_CATMULL_ROM_SAMPLES)
    uint Count;

    // Constant sign of the UV direction from master UV sampling location.
    int2 UVDir[BICUBIC_CATMULL_ROM_SAMPLES];

    // Bilinear sampling UV coordinates of the samples
    float2 UV[BICUBIC_CATMULL_ROM_SAMPLES];

    // Weights of the samples
    float Weight[BICUBIC_CATMULL_ROM_SAMPLES];

    // Final multiplier (it is faster to multiply 3 RGB values than reweights the 5 weights)
    float FinalMultiplier;
};

float3 ImportanceSampleGGX_SSR(float2 random, float3 normalWS, float3 viewDirWS, float roughness, out bool valid)
{
    float alpha2 = roughness * roughness;
    float alpha4 = alpha2 * alpha2;

    half3x3 locaToWorld = GetLocalFrame(normalWS);
    float VoH;
    float3 localV, localH;
    SampleGGXVisibleNormal(random, -viewDirWS, locaToWorld, alpha2, localV, localH, VoH);
    // SampleAnisoGGXVisibleNormal(random, -viewDirWS, locaToWorld, alpha2, alpha2, localV, localH, VoH);

    float3 localL = 2.0 * VoH * localH - localV;
    float3 outDirWS = mul(localL, locaToWorld);
    float NoL = dot(normalWS, outDirWS);

    valid = (NoL >= 0.0001);

    return outDirWS;
}

float4 ImportanceSampleGGX_SSR(float2 random, float roughness)
{
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

///////////////// BicubicSampler
void Bicubic2DCatmullRom(in float2 UV, in float2 Size, in float2 InvSize, out float2 Sample[3], out float2 Weight[3])
{
    UV *= Size;

    float2 tc = floor(UV - 0.5) + 0.5;
    float2 f = UV - tc;
    float2 f2 = f * f;
    float2 f3 = f2 * f;

    float2 w0 = f2 - 0.5 * (f3 + f);
    float2 w1 = 1.5 * f3 - 2.5 * f2 + 1;
    float2 w3 = 0.5 * (f3 - f2);
    float2 w2 = 1 - w0 - w1 - w3;

    Weight[0] = w0;
    Weight[1] = w1 + w2;
    Weight[2] = w3;

    Sample[0] = tc - 1;
    Sample[1] = tc + w2 / Weight[1];
    Sample[2] = tc + 2;

    Sample[0] *= InvSize;
    Sample[1] *= InvSize;
    Sample[2] *= InvSize;
}

FCatmullRomSamples GetBicubic2DCatmullRomSamples(float2 UV, float2 Size, in float2 InvSize)
{
    FCatmullRomSamples Samples;
    Samples.Count = BICUBIC_CATMULL_ROM_SAMPLES;

    float2 Weight[3];
    float2 Sample[3];
    Bicubic2DCatmullRom(UV, Size, InvSize, Sample, Weight);

    // Optimized by removing corner samples
    Samples.UV[0] = float2(Sample[1].x, Sample[0].y);
    Samples.UV[1] = float2(Sample[0].x, Sample[1].y);
    Samples.UV[2] = float2(Sample[1].x, Sample[1].y);
    Samples.UV[3] = float2(Sample[2].x, Sample[1].y);
    Samples.UV[4] = float2(Sample[1].x, Sample[2].y);

    Samples.Weight[0] = Weight[1].x * Weight[0].y;
    Samples.Weight[1] = Weight[0].x * Weight[1].y;
    Samples.Weight[2] = Weight[1].x * Weight[1].y;
    Samples.Weight[3] = Weight[2].x * Weight[1].y;
    Samples.Weight[4] = Weight[1].x * Weight[2].y;

    Samples.UVDir[0] = int2( 0, -1);
    Samples.UVDir[1] = int2(-1,  0);
    Samples.UVDir[2] = int2( 0,  0);
    Samples.UVDir[3] = int2( 1,  0);
    Samples.UVDir[4] = int2( 0,  1);

    // Reweight after removing the corners
    float CornerWeights;
    CornerWeights  = Samples.Weight[0];
    CornerWeights += Samples.Weight[1];
    CornerWeights += Samples.Weight[2];
    CornerWeights += Samples.Weight[3];
    CornerWeights += Samples.Weight[4];
    Samples.FinalMultiplier = 1 / CornerWeights;

    return Samples;
}