Shader "Hidden/ArtSSR/HizCompute"
{
    Properties { }

    SubShader
    {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        ENDHLSL

        Pass
        {
            Name "HiZCompute"
            
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment HiZComputeFragment

            Texture2D _DepthPyramid;
            SamplerState sampler_DepthPyramid;

            CBUFFER_START(UnityPerMaterial)
                int _HiZPrevDepthLevel;
            CBUFFER_END

            float4 HiZComputeFragment(Varyings fsIn) : SV_Target
            {
                float2 screenUV = fsIn.texcoord;

                float depth0 = _DepthPyramid.SampleLevel(sampler_DepthPyramid, screenUV, _HiZPrevDepthLevel, int2(-1.0, -1.0)).r;
                float depth1 = _DepthPyramid.SampleLevel(sampler_DepthPyramid, screenUV, _HiZPrevDepthLevel, int2( 1.0, -1.0)).r;
                float depth2 = _DepthPyramid.SampleLevel(sampler_DepthPyramid, screenUV, _HiZPrevDepthLevel, int2(-1.0,  1.0)).r;
                float depth3 = _DepthPyramid.SampleLevel(sampler_DepthPyramid, screenUV, _HiZPrevDepthLevel, int2( 1.0,  1.0)).r;

                float maxValue = max(max(depth0, depth1), max(depth2, depth3));
                return maxValue;
            }

            ENDHLSL
        }
    }
}