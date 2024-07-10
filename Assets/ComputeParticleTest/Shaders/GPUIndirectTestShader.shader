Shader "Custom/GPUIndirectTestShader"
{
    Properties
    {
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
    }
    
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        void Rotate2D(inout float2 v, float r)
        {
            float s, c;
            sincos(r, s, c);
            v = float2(dot(v, float2(c, -s)), dot(v, float2(s, c)));
        }
        
        ENDHLSL

        Pass
        {
             HLSLPROGRAM

             #pragma target 4.5
             #pragma vertex VertexPass
             #pragma fragment FragmentPass

             TEXTURE2D(_MainTex);           SAMPLER(sampler_MainTex);

             StructuredBuffer<float4> PositionBuffer;

             struct Attributes
             {
                 float4 positionOS : POSITION;
                 float2 texCoord : TEXCOORD0;
                 uint instanceID : SV_InstanceID;
             };

             struct Varyings
             {
                 float4 positionCS : SV_POSITION;
                 float2 texCoord : TEXCOORD0;
             };

             Varyings VertexPass(Attributes vsIn)
             {
                 float4 pos = PositionBuffer[vsIn.instanceID];
                 float rotation = pos.w * pos.w * _Time.y * 0.5f;
                 Rotate2D(pos.xz, rotation);

                 float3 posOS = vsIn.positionOS.xyz * pos.w;
                 float3 posWS = pos.xyz + posOS;

                 Varyings vsOut = (Varyings)0;
                 vsOut.positionCS = mul(UNITY_MATRIX_VP, float4(posWS, 1.));
                 vsOut.texCoord = vsIn.texCoord;
                 return vsOut;
             }

             half4 FragmentPass(Varyings fsIn) : SV_Target
             {
                 half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);
                 return color;
             }
        
             ENDHLSL
        }
    }
}