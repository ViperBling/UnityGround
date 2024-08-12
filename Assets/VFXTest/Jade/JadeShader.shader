Shader "Unlit/JadeShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 texCoord   : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texCoord   : TEXCOORD0;
                
            };

            Varyings VertexPass (Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;
                
                vsOut.positionCS = TransformObjectToHClip(vsIn.positionOS.xyz);
                vsOut.texCoord = TRANSFORM_TEX(vsIn.texCoord, _MainTex);
                return vsOut;
            }

            half4 FragmentPass (Varyings fsIn) : SV_Target
            {
                half4 finalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);
                return finalColor;
            }
            ENDHLSL
        }
    }
}
