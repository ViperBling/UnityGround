Shader "Unlit/S_Trail"
{
    Properties
    {
        _SDFTex0 ("_SDFTex0", 2D) = "white" {}
        _SDFTex1 ("_SDFTex1", 2D) = "white" {}
        _Blend ("Blend", Range(0, 1)) = 0
        _Step ("Step", Range(0.000001, 1)) = 0
    }
    SubShader
    {
        Tags { "RanderPipline" = "UniversalPipeline" "RanderType" = "Opaque" }
        LOD 100
        
        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _Blend;
                float _Step;
            CBUFFER_END

            TEXTURE2D(_SDFTex0);        SAMPLER(sampler_SDFTex0);
            TEXTURE2D(_SDFTex1);        SAMPLER(sampler_SDFTex1);
        ENDHLSL

        Pass
        {
            Name "ForwardUnlit"
//            Tags {"LightMode" = "UniversalForward"}
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 PositionOS : POSITION;
                float2 TexCoord : TEXCOORD0;
            };

            struct Varyings
            {
                float4 PositionCS : SV_POSITION;
                float2 TexCoord : TEXCOORD0;
            };

            Varyings vert (Attributes vsIn)
            {
                const VertexPositionInputs vertexInput = GetVertexPositionInputs(vsIn.PositionOS);
                Varyings vsOut;
                vsOut.TexCoord = vsIn.TexCoord;
                vsOut.PositionCS = vertexInput.positionCS;
                return vsOut;
            }

            half4 frag (Varyings psIn) : SV_Target
            {
                half4 sdf0 = SAMPLE_TEXTURE2D(_SDFTex0, sampler_SDFTex0, psIn.TexCoord);
                half4 sdf1 = SAMPLE_TEXTURE2D(_SDFTex1, sampler_SDFTex1, psIn.TexCoord);

                sdf0.r = pow(sdf0.r, 0.1);
                sdf1.r = pow(sdf1.r, 0.5);
                
                half sdf = lerp(sdf0.r, sdf1.r, _Blend);
                half finalColor = step(_Step, sdf);
                
                return half4(finalColor.xxx, 1);
            }
            ENDHLSL
        }
    }
}
