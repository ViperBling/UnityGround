#pragma once

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
            #define OUTPUT_SHADOW_COORD_VERTEX(positionWS, positionCS, shadowCoord) shadowCoord = ComputeScreenPos(positionCS);
        #elif defined(_HD_SHADOW_RECEIVER)
            #define OUTPUT_SHADOW_COORD_VERTEX(positionWS, positionCS, shadowCoord) shadowCoord = TransformWorldToHDShadowCoord(positionWS);
        #else
            #define OUTPUT_SHADOW_COORD_VERTEX(positionWS, positionCS, shadowCoord) shadowCoord = TransformWorldToShadowCoord_URP(positionWS);
        #endif
        #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
            #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) shadowCoord;
        #else
            #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) shadowCoord;
        #endif
    #else
        #define OUTPUT_SHADOW_COORD_VERTEX(positionWS, shadowCoord)
        #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
            #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) shadowCoord;
        #elif defined(_MAIN_LIGHT_SHADOWS_SCREEN)
             #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) ComputeScreenPos(positionCS);
        #elif defined(_HD_SHADOW_RECEIVER)
            #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) TransformWorldToHDShadowCoord(positionWS);
        #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
            #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) TransformWorldToShadowCoord_URP(positionWS);
        #else
            #define OUTPUT_SHADOW_COORD_FRAGMENT(positionWS, positionCS, shadowCoord) float4(0,0,0,0);
        #endif
    #endif
#endif

#ifdef INSTANCING_ON
    #define DECLARE_LIGHTMAP_OR_SH_PWRD(lmName, shName, index) float2 lmName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV_PWRD(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * lightmapScaleOffset.xy + lightmapScaleOffset.zw;
    #define OUTPUT_SH_PWRD(normalWS, OUT)
#elif defined(LIGHTMAP_ON) && !(CUSTOM_NO_LIGHTMAP)
    #define DECLARE_LIGHTMAP_OR_SH_PWRD(lmName, shName, index) float2 lmName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV_PWRD(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * lightmapScaleOffset.xy + lightmapScaleOffset.zw;
    #define OUTPUT_SH_PWRD(normalWS, OUT)
#elif defined(CUSTOM_NO_LIGHTMAP)
    #define DECLARE_LIGHTMAP_OR_SH_PWRD(lmName, shName, index) half3 shName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV_PWRD(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * lightmapScaleOffset.xy + lightmapScaleOffset.zw;
    #define OUTPUT_SH_PWRD(normalWS, OUT) OUT.xyz = SampleSHVertex(normalWS)
#elif defined(FORCE_LIGHTMAP)
    #define DECLARE_LIGHTMAP_OR_SH_PWRD(lmName, shName, index) float2 lmName : TEXCOORD##index
    //URP SRP Batch后lightmapScaleOffset 无故被换成0,0导致黑色
    //#define OUTPUT_LIGHTMAP_UV_PWRD(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * half2(1.0,1.0) + lightmapScaleOffset.zw;
    #define OUTPUT_LIGHTMAP_UV_PWRD(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * lightmapScaleOffset.xy + lightmapScaleOffset.zw;
    #define OUTPUT_SH_PWRD(normalWS, OUT)
#else
    #define DECLARE_LIGHTMAP_OR_SH_PWRD(lmName, shName, index) half3 shName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV_PWRD(lightmapUV, lightmapScaleOffset, OUT)
    #define OUTPUT_SH_PWRD(normalWS, OUT) OUT.xyz = SampleSHVertex(normalWS)
#endif