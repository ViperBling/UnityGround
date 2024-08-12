Shader "VFXTest/JadeShader"
{
    Properties
    {
        _MainTex ("Main Textuer", 2D) = "white" {}
        _NormalMap ("Normal Texture", 2D) = "bump" {}
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);      SAMPLER(sampler_NormalMap);
            
            float4 _MainTex_ST;
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                half3 normalOS    : NORMAL;
                float2 texCoord   : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texCoord   : TEXCOORD0;
                float4 tSpace0    : TEXCOORD1;
                float4 tSpace1    : TEXCOORD2;
                float4 tSpace2    : TEXCOORD3;
            };

            float3 WorldNormal(Varyings input, float3 normal)
            {
            	return normalize(float3(dot(input.tSpace0.xyz, normal), dot(input.tSpace1.xyz, normal), dot(input.tSpace2.xyz, normal)));
            }

            Varyings VertexPass (Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;
                
                vsOut.positionCS = TransformObjectToHClip(vsIn.positionOS.xyz);
                vsOut.texCoord = TRANSFORM_TEX(vsIn.texCoord, _MainTex);
                float3 positionWS = TransformObjectToWorld(vsIn.positionOS);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(vsIn.normalOS);
                vsOut.tSpace0 = float4(normalInputs.tangentWS.x, normalInputs.bitangentWS.x, normalInputs.normalWS.x, positionWS.x);
                vsOut.tSpace1 = float4(normalInputs.tangentWS.y, normalInputs.bitangentWS.y, normalInputs.normalWS.y, positionWS.y);
                vsOut.tSpace2 = float4(normalInputs.tangentWS.z, normalInputs.bitangentWS.z, normalInputs.normalWS.z, positionWS.z);
                
                return vsOut;
            }

            half4 FragmentPass (Varyings fsIn) : SV_Target
            {
                float3 positionWS = float3(fsIn.tSpace0.w, fsIn.tSpace1.w, fsIn.tSpace2.w);
                half3 lightDir = GetMainLight().direction;

                half4 normalTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, fsIn.texCoord);
                half3 normalTS = UnpackNormalScale(normalTex, 1.0);
                half3 normalWS = WorldNormal(fsIn, normalTS);

                half diffuse = max(0.0, dot(normalWS, lightDir));
                
                half4 finalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);

                finalColor *= diffuse;
                return finalColor;
            }
            ENDHLSL
        }
    }
}
