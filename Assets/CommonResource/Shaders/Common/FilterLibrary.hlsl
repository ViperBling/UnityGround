#pragma once 

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Assets/CommonResource/Shaders/Common/Common.hlsl"

inline float HDRWeight4(float3 color, float exposure)
{
    return rcp(Luma4(color) * exposure + 4);
}