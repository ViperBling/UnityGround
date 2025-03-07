Shader "Hidden/ArtSSRShader"
{
    Properties 
    {
        [HideInInspector] _RandomSeed("Random Seed", Float) = 0.0
    }
    
    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Never
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
        ENDHLSL
        
        Pass
        {
            Name "Linear View Space Tracing"
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment LinearVSTracingPass

            // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
            // 这个宏定义具体的解码方式
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            
            ENDHLSL
        }

        Pass
        {
            Name "Linear Screen Space Tracing"
            
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
            Name "HiZ Tracing"
            
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
        
        Pass
        {
            Name "Composite"
            
            Blend SrcAlpha OneMinusSrcAlpha, SrcAlpha SrcAlpha
            
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