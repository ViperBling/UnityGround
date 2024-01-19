Shader "UnityGround/PRTComposite"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        
        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/PRT/Shaders/SH.hlsl"

            sampler2D _MainTex;
            
            TEXTURE2D_X(_CameraDepthTexture);
            TEXTURE2D_X_HALF(_GBuffer0);
            TEXTURE2D_X_HALF(_GBuffer1);
            TEXTURE2D_X_HALF(_GBuffer2);

            float4x4 _ScreenToWorld[2];
            SamplerState sampler_point_clamp;

            float _CoefficientVoxelGridSize;
            float4 _CoefficientVoxelCorner;
            float4 _CoefficientVoxelSize;
            StructuredBuffer<int> _CoefficientVoxel;
            StructuredBuffer<int> _LastFrameCoefficientVoxel;

            float _GIIntensity;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            float4 GetFragmentWorldPos(float2 screenPos)
            {
                float screenRawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_point_clamp, screenPos);
                float4 ndc = float4(screenPos.x * 2 - 1, screenPos.y * 2 - 1, screenRawDepth, 1);
                #if UNITY_UV_STARTS_AT_TOP
                    ndc.y *= -1;
                #endif
                float4 worldPos = mul(UNITY_MATRIX_I_P, ndc);
                worldPos /= worldPos.w;
                
                return worldPos;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 color = tex2D(_MainTex, i.uv);

                float4 worldPos = GetFragmentWorldPos(i.uv);
                float3 albedo = SAMPLE_TEXTURE2D_X_LOD(_GBuffer0, sampler_point_clamp, i.uv, 0).xyz;
                float3 normal = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_point_clamp, i.uv, 0).xyz;

                float3 gi = SampleSHVoxel(
                    worldPos,
                    albedo,
                    normal,
                    _CoefficientVoxel,
                    _CoefficientVoxelSize,
                    _CoefficientVoxelCorner,
                    _CoefficientVoxelGridSize);
                color.rgb += gi * _GIIntensity;

                return color;
            }
            
            ENDHLSL
        }
    }
}