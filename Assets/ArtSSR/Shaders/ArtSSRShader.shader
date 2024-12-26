Shader "Hidden/ArtSSRShader"
{
    Properties {}
    
    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Never
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"
        ENDHLSL
        
        Pass
        {
            Name "Linear SSR"
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma vertex VertexPass
            #pragma fragment LinearFragmentPass

            // 在使用了Accurate GBuffer Normal的情况下，需要解码法线
            // 这个宏定义具体的解码方式
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            // #include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
            #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
            
            ENDHLSL
        }
        
        Pass
        {
            Name "HiZ SSR"
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma vertex VertexPass
            #pragma fragment HiZFragmentPass

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            #include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
            #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
            
            ENDHLSL
        }
        
        Pass
        {
            Name "Composite"
            
            HLSLPROGRAM

            #pragma enable_d3d11_debug_symbols
            #pragma vertex VertexPass
            #pragma fragment CompositeFragmentPass

            #include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
            #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
            
            ENDHLSL
        }
    }
}