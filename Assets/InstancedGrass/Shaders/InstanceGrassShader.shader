Shader "PBR/MeshGrass"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" { }
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
        ENDHLSL

        Pass
        {
            Cull Back //use default culling because this shader is billboard 
            ZTest Less
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fog

            CBUFFER_START(UnityPerMaterial)
                StructuredBuffer<float3> _InstancePositionBuffer;
                StructuredBuffer<uint> _VisibleInstanceIndexBuffer;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 texCoord : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texCoord : TEXCOORD0;
            };

            Varyings VertexPass(Attributes vsIn, uint instanceID : SV_InstanceID)
            {
                Varyings vsOut = (Varyings)0;
                float3 perGrassPivotPosWS = _InstancePositionBuffer[_VisibleInstanceIndexBuffer[instanceID]];

                float3 cameraTransformRightWS = UNITY_MATRIX_V[0].xyz;          //UNITY_MATRIX_V[0].xyz == world space camera Right unit vector
                float3 cameraTransformUpWS = UNITY_MATRIX_V[1].xyz;             //UNITY_MATRIX_V[1].xyz == world space camera Up unit vector
                float3 cameraTransformForwardWS = -UNITY_MATRIX_V[2].xyz;       //UNITY_MATRIX_V[2].xyz == -1 * world space camera Forward unit vector

                float3 positionOS = vsIn.positionOS.x * cameraTransformRightWS * (sin(perGrassPivotPosWS.x * 95.4643 + perGrassPivotPosWS.z) * 0.45 + 0.55);    //random w
                positionOS += vsIn.positionOS.y * cameraTransformUpWS;

                vsOut.positionCS = TransformObjectToHClip(positionOS.xyz);
                vsOut.texCoord = vsIn.texCoord;
                return vsOut;
            }

            float4 FragmentPass(Varyings fsIn) : SV_Target
            {
                return float4(fsIn.positionCS.xyz, 1.0);
            }

            ENDHLSL
        }
    }
}
