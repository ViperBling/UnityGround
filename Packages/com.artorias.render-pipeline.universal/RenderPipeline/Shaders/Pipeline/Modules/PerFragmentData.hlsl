#pragma once

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct PerFragmentData
{
    Varyings    varyingInput;
    InputData   inputData;
    SurfaceData surfaceData;
    BRDFData    brdfData;
    BRDFData    clearCoatMask;

    Light       mainLight;

    half3       indirectDiffuse;
    half3       indirectSpecular;
    half3       indirectColor;

    half3       directDiffuse;        //直射光漫反射是辐照度之前的 并非最终值
    half3       directSpecular;       //直射光高光是辐照度之前的 并非最终值
    half3       directColor;

    #if defined(CUSTOM_FRAGMENT_DATA)
        CUSTOM_FRAGMENT_DATA
    #endif
};