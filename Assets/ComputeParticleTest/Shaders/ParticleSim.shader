Shader "ParticleSim/ParticlShader"
{
    Properties
    {
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
    }
    
    SubShader
    {
        Tags
        {
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
            "IgnoreProjector" = "True"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Cull Off
        Blend SrcAlpha One
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        ENDHLSL
        
        Pass
        {
            HLSLPROGRAM

            #pragma target 5.0

            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            StructuredBuffer<float3> PositionBuffer;
            StructuredBuffer<float3> ColorBuffer;
            
            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half3 vertexColor : COLOR;
            };

            Varyings VertexPass(Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;

                float3 positionWS = PositionBuffer[vsIn.vertexID];
                vsOut.positionCS = TransformWorldToHClip(positionWS);
                vsOut.vertexColor = ColorBuffer[vsIn.vertexID];

                return vsOut;
            }

            float4 FragmentPass(Varyings fsIn) : SV_Target
            {
                return float4(fsIn.vertexColor, 0.8);
            }
            
            ENDHLSL
        }
    }
}