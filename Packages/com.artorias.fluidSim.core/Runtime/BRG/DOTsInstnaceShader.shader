Shader "ArtFluidSim/DOTsInstance"
{
    Properties
    {
        _BaseColor ("Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Pass
        {
            HLSLPROGRAM

            #pragma target 4.5
            #pragma multi_compile DOTS_INSTANCING_ON

            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
            UNITY_DOTS_INSTANCED_PROP(float4, _BaseColor)
            UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float4x4 objectToWorld = UNITY_DOTS_MATRIX_M;

                float4 positionWS = mul(objectToWorld, float4(input.positionOS.xyz, 1.0));
                output.positionCS = mul(unity_MatrixVP, positionWS);

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float4 color = UNITY_ACCESS_DOTS_INSTANCED_PROP(float4, _BaseColor);
                return half4(color.rgb, 1.0);
            }
            
            ENDHLSL
        }
    }
}