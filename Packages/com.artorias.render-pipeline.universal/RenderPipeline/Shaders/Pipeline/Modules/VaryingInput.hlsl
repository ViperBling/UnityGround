#pragma once

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 uv0          : TEXCOORD0;
    float2 lightmapUV1  : TEXCOORD1;
    float2 lightmapUV2  : TEXCOORD2;
    #if defined(REQUIRES_VERTEX_COLOR)
        float4 color        : COLOR;
    #endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    #if defined(REQUIRES_UV_FLOAT4)
        float4 uv                   : TEXCOORD0;
    #else
        float2 uv                   : TEXCOORD0;
    #endif

    float2 lightmapUV1              : TEXCOORD1;
    float3 vertexSH                 : TEXCOORD2;

    #if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
        float3 positionWS           : TEXCOORD3;
    #endif

    float3 normalWS                 : TEXCOORD4;

    #if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
        float4 tangentWS            : TEXCOORD5;                  // xyz : tangent, w : sgn
        float3 bitangentWS          : TEXCOORD6;
    #endif

    float3 viewDirWS                : TEXCOORD7;
    half4 fogFactorAndVertexLight   : TEXCOORD8;                  // x : fog factor, yzw : vertex light

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        float4 shadowCoord          : TEXCOORD9;
    #endif

    #if defined(SKYLIGHT_SH_ON)
        half3 vertexSkyLightSH      : TEXCOORD10;
    #endif

    #if defined(REQUIRES_SCREEN_SPACE_INTERPOLATORS)
        float3 screenPos            : TEXCOORD11;
    #endif

        float4 positionCS           : SV_POSITION;

    #if defined(CUSTOM_VARYING)
        CUSTOM_VARYING
    #endif

    // DEBUG_OUTPUT_COORDS(14, 15)

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

#include "Packages/com.artorias.render-pipeline.universal/Shaders/Pipeline/Modules/PerFragmentData.hlsl"
#include "Packages/com.artorias.render-pipeline.universal/Shaders/Pipeline/Modules/FunctionDeclaration.hlsl"