#pragma once

CBUFFER_START(UnityPerMaterial)

    half _ReceiveShadows;

    #define INSERT_PER_MATERIAL
        #include "Packages/com.artorias.render-pipeline.universal/Shaders/Pipeline/Modules/FeaturesPCH.hlsl" 
    #undef INSERT_PER_MATERIAL

    #if defined(INSERT_PER_SURFACE)
        INSERT_PER_SURFACE
    #endif

CBUFFER_END

#if defined(UNITY_ANY_INSTANCING_ENABLED)
    UNITY_INSTANCING_BUFFER_START(UnityPerInstance)
    
    #define INSERT_PER_INSTANCE
        #include "Packages/com.artorias.render-pipeline.universal/Shaders/Pipeline/Modules/FeaturesPCH.hlsl"
    #undef INSERT_PER_INSTANCE
    
    #if defined(INSERT_PER_SURFACE_INSTANCE)
        INSERT_PER_SURFACE_INSTANCE
    #endif
    
    UNITY_INSTANCING_BUFFER_END(UnityPerInstance)
#endif


#define ATFEATURE_INCLUDE
#include "Packages/com.artorias.render-pipeline.universal/Shaders/Pipeline/Modules/FeaturesPCH.hlsl"
#undef ATFEATURE_INCLUDE