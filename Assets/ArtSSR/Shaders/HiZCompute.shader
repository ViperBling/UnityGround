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

            #pragma enable_d3d11_debug_symbols
            #pragma vertex Vert
            #pragma fragment HiZComputeFragment

            // Texture2D _DepthPyramid;
            SamplerState sampler_BlitTexture;

            // CBUFFER_START(UnityPerMaterial)
                int _HiZPrevDepthLevel;
            // CBUFFER_END

            float4 HiZComputeFragment(Varyings fsIn) : SV_Target
            {
                float2 screenUV = fsIn.texcoord;
                
                // 从上一级MIP进行2x2采样
                // 正确计算偏移，确保我们访问子像素
                float2 texelSize = 1.0 / _ScreenParams.xy;
                float2 halfTexelSize = texelSize * 0.5;
                
                // 采样2x2区域内的4个像素
                float depth0 = _BlitTexture.SampleLevel(sampler_BlitTexture, screenUV, _HiZPrevDepthLevel).r;
                float depth1 = _BlitTexture.SampleLevel(sampler_BlitTexture, screenUV + float2(texelSize.x, 0), _HiZPrevDepthLevel).r;
                float depth2 = _BlitTexture.SampleLevel(sampler_BlitTexture, screenUV + float2(0, texelSize.y), _HiZPrevDepthLevel).r;
                float depth3 = _BlitTexture.SampleLevel(sampler_BlitTexture, screenUV + texelSize, _HiZPrevDepthLevel).r;
                
                // 使用max而不是min，因为Unity的深度图是反向的(1=近，0=远)
                float maxDepth = max(max(depth0, depth1), max(depth2, depth3));
                return maxDepth;
            }

            ENDHLSL
        }
    }
}