Shader "Hidden/Lighting/SSRShader"
{
    Properties
    {
		[HideInInspector] _MinSmoothness("Minimum Smoothness", Float) = 0.4
        [HideInInspector] _FadeSmoothness("Smoothness Fade Start", Float) = 0.6
		[HideInInspector] _EdgeFade("Screen Edge Fade Distance", Float) = 0.1
		[HideInInspector] _Thickness("Object Thickness", Float) = 0.25
		[HideInInspector] _StepStride("Step Size", Float) = 0.4
		[HideInInspector] _MaxSteps("Max Ray Steps", Float) = 16.0
		[HideInInspector] _DownSample("Private: Ray Marching Resolution", Float) = 1.0
    }
    
    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Always
        Blend One Zero
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
        // The Blit.hlsl file provides the vertex shader (Vert),
        // input structure (Attributes) and output strucutre (Varyings)
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        ENDHLSL
        
        Pass
        {
            Name "SSR Approximation"
            
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment SSRFragment

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile_local_fragment _ _BACKFACE_ENABLED

            #include "Assets/SSR/Resources/SSR.hlsl"
            
            ENDHLSL
        }

        Pass
        {
            Name "SSR Composite"
            
            Blend SrcAlpha OneMinusSrcAlpha, SrcAlpha SrcAlpha
            
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment CompositeFragment

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile_local_fragment _ _SSR_APPROX_COLOR_MIPMAP

            #include "Assets/SSR/Resources/SSR.hlsl"

            ENDHLSL
        }
    }
}