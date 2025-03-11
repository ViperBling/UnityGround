#pragma once 

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

float GenerateRandomFloat(float2 uv, float2 resolution, inout int randomSeed)
{
    float time = unity_DeltaTime.y * _Time.y + randomSeed++;
    return GenerateHashedRandomFloat(uint3(uv * resolution, time));
}

float GetHaltonValue(int index, int radix)
{
    float result = 0.0;
    float fraction = 1.0 / radix;

    while (index > 0)
    {
        result += fraction * (index % radix);
        index /= radix;
        fraction /= radix;
    }
    return result;
}

float2 GenerateRandomOffset(inout int randomSeed)
{
    float u = GetHaltonValue(randomSeed & 1023, 2);
    float v = GetHaltonValue(randomSeed & 1023, 3);
    if (randomSeed++ >= 64)
    {
        randomSeed = 0;
    }
    return float2(u, v);
}