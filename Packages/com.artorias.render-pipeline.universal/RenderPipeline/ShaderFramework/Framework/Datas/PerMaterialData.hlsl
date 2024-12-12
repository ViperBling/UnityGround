#pragma once

CBUFFER_START(UnityPerMaterial)

#define ATRP_INSERT_PER_MATERIAL
    #include "Packages/com.artorias.render-pipeline.universal/RenderPipeline/ShaderFramework/Configs/ShaderSurfaceDataInputs.hlsl"
#undef ATRP_INSERT_PER_MATERIAL

#if defined(CUSTOM_UNITY_PER_MATERIAL)
    CUSTOM_UNITY_PER_MATERIAL
#endif

    int _ReceiveNoShadow;
    int _AlphaBlend_On;

CBUFFER_END

#if defined(UNITY_INSTANCING_ENABLED)

    UNITY_INSTANCING_BUFFER_START(UnityPerInstance)
        #define ATRP_INSERT_PER_INSTANCE
        #undef ATRP_INSERT_PER_INSTANCE

        #if defined (CUSTOM_UNITY_PER_INSTANCE)
            CUSTOM_UNITY_PER_INSTANCE
        #endif
    UNITY_INSTANCING_BUFFER_END(UnityPerInstance)

#endif