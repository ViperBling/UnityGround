#pragma once

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"

float D_GGX_SSR(float NoH, float roughness)
{
    float a2 = roughness * roughness;
    float D = (NoH * a2 - NoH) * NoH + 1.0; // 1.0 is the NoH^2 term

    return INV_PI * a2 / (D * D + 1e-7f);
}

float Vis_SmithGGXCorrelated_SSR(float NoL, float NoV, float roughness)
{
    float a = roughness;
    float a2 = a * a;
    float LambdaL = NoV * (NoL * (1 - a) + a);
	float LambdaV = NoL * (NoV * (1 - a) + a);
    
	return (0.5f / (LambdaL + LambdaV + 1e-7f));
}