#pragma once

struct FGIData
{
    half shadowMask;
    half staticLightArea;
    half bakedAO;
    half skyOcculsion;
    half bakedGI;
    half mainLightDir;
    half mainLightColor;
    half skylightGI;
    half finalGI;
};

struct FFragmentData
{
    float2 texCoord;
    float2 lightmapUV;
    float3 normalWS;
    float3 positionWS;
    float3 viewDirWS;
    float4 shadowCoord;
    half fogFactor;
    half3 vertexLight;
    float NoL;
    FGIData giData;
    BRDFData brdfData;
    SurfaceData surfaceData;

#if defined(CUSTOM_FRAGMENT_DATA)
    CUSTOM_FRAGMENT_DATA
#endif

#if defined(REQUIRE_VFACE)
    half vface;
#endif
};