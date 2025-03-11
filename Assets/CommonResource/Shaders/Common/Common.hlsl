#pragma once 

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

inline float Luma4(float3 color)
{
    return color.g * 2 + color.r + color.b;
}