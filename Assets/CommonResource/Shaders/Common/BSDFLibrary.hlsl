#pragma once

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"

float D_GGX_SSR(float NoH, float roughness)
{
    float a4 = Pow4(roughness);
    float D = (NoH * a4 - NoH) * NoH + 1.0; // 1.0 is the NoH^2 term

    return a4 / (PI * D * D);
}

float Vis_SmithGGXCorrelated_SSR(float NoL, float NoV, float roughness)
{
    float a2 = roughness * roughness;
    float LambdaL = NoV * sqrt((1 - a2) * NoL * NoL + a2);
	float LambdaV = NoL * sqrt((1 - a2) * NoV * NoV + a2);
    
	return (0.5 / max((LambdaL + LambdaV), REAL_MIN)) / PI;
}