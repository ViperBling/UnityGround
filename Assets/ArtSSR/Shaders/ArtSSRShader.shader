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
        ENDHLSL
        
        Pass
        {
            Name "Linear SSR"
            
            HLSLPROGRAM

            // #pragma enable_d3d11_debug_symbols
            #pragma vertex VertexPass
            #pragma fragment LinearFragmentPass

            #include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
            #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
            
            ENDHLSL
        }
        
        Pass
        {
            Name "HiZ SSR"
            
            HLSLPROGRAM

            // #pragma enable_d3d11_debug_symbols
            #pragma vertex VertexPass
            #pragma fragment HiZFragmentPass

            #include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
            #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
            
            ENDHLSL
        }
        
        Pass
        {
            Name "Composite"
            
            HLSLPROGRAM

            // #pragma enable_d3d11_debug_symbols
            #pragma vertex VertexPass
            #pragma fragment CompositeFragmentPass

            #include "Assets/ArtSSR/Shaders/Common/ArtSSRInput.hlsl"
            #include "Assets/ArtSSR/Shaders/Common/ArtSSR.hlsl"
            
            ENDHLSL
        }
    }
}