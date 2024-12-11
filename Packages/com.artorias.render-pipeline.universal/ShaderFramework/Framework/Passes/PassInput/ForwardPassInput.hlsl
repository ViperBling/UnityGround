#pragma once

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.artorias.render-pipeline.universal/ShaderFramework/Framework/Datas/FragmentData.hlsl"

#define REQUIRES_VERTEX_TEXCOORD1_ATTRIBUTE (defined(LIGHTMAP_ON)

struct FAttributes
{
    float4 positionOS   : POSITION;
    float2 texCoord     : TEXCOORD0;

    float3 normalOS     : NORMAL;

#if defined(REQUIRES_VERTEX_TANGENT_ATTRIBUTE)
    float4 tangentOS    : TANGENT;
#endif

#if REQUIRES_VERTEX_TEXCOORD1_ATTRIBUTE
    float2 lightmapUV   : TEXCOORD1;
#endif

#if defined(REQUIRES_VERTEX_COLOR_ATTRIBUTE)
    float4 vertexColor        : COLOR;
#endif

#if defined(CUSTOM_ATTRIBUTES)
    CUSTOM_ATTRIBUTES
#endif
};

#include "Packages/com.artorias.render-pipeline.universal/ShaderFramework/Framework/Datas/PerMaterialData.hlsl"