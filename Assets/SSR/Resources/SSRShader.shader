Shader "Hidden/SSRShader"
{
    Properties
    {

    }
    
    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Always
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        #include "Assets/SSR/Resources/SSR.hlsl"
        ENDHLSL
        
        Pass
        {
            Name "Linear Screen Space Tracing 0"
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment LinearSSTracingPass

            // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
            // 这个宏定义具体的解码方式
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            
            ENDHLSL
        }
        
        Pass
        {
            Name "HiZ Tracing 1"
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment HiZTracingPass

            // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
            // 这个宏定义具体的解码方式
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            ENDHLSL
        }

        // Pass
        // {
        //     Name "Spatio Filter 2"
            
        //     HLSLPROGRAM

        //     #pragma enable_d3d11_debug_symbols
        //     #pragma target 3.5
        //     #pragma vertex Vert
        //     #pragma fragment SpatioFilterPass

        //     // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
        //     // 这个宏定义具体的解码方式
        //     #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

        //     ENDHLSL
        // }

        // Pass
        // {
        //     Name "Temporal Filter 3"

        //     HLSLPROGRAM

        //     #pragma enable_d3d11_debug_symbols
        //     #pragma target 3.5
        //     #pragma vertex Vert
        //     #pragma fragment TemporalFilterPass

        //     // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
        //     // 这个宏定义具体的解码方式
        //     #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

        //     ENDHLSL
        // }
        
        Pass
        {
            Name "Composite 4"
            
            // Blend SrcAlpha OneMinusSrcAlpha, SrcAlpha SrcAlpha
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment CompositeFragmentPass

            // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
            // 这个宏定义具体的解码方式
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile_fragment _ DITHER_8x8 DITHER_INTERLEAVED_GRADIENT
            
            ENDHLSL
        }
    }
}