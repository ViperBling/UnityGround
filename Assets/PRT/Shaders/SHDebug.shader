Shader "UnityGround/SHDebug"
{
    Properties
    {
        
    }
    SubShader
    {
        Tags{ "RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline" "Queue" = "Geometry" }
        LOD 100
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/PRT/Shaders/SH.hlsl"

            CBUFFER_START(UnityPerMaterial)
                StructuredBuffer<int> _CoefficientSH9;
            CBUFFER_END

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };
            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD2;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.normal = TransformObjectToWorldNormal(v.normal);
                o.normal = normalize(o.normal);
                return o;
            }

            float4 frag (v2f vsOut) : SV_Target
            {
                float3 dir = vsOut.normal;

                float3 c[9];
                for (int i = 0; i < 9; i++)
                {
                    c[i].x = DecodeFloatFromInt(_CoefficientSH9[i * 3 + 0]);
                    c[i].y = DecodeFloatFromInt(_CoefficientSH9[i * 3 + 1]);
                    c[i].z = DecodeFloatFromInt(_CoefficientSH9[i * 3 + 2]);
                }
                float3 irradiance = IrradianceSH9(c, dir);
                float3 Lo = irradiance / PI;

                return float4(Lo, 1.0);
            }

            ENDHLSL
        }
        
    }
}