Shader "UnityGround/PRTComposite"
{
    Properties
    {
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
            
            TEXTURE2D_X(_CameraDepthTexture);
            TEXTURE2D_X(_GBuffer0);
            TEXTURE2D_X(_GBuffer1);
            TEXTURE2D_X(_GBuffer2);

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
                float4 ndc = float4(screenPos.x * 2 - 1, screenPos.y * 2 - 1, screenRawDepth, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                    ndc.y *= -1;
                #endif
                float4 worldPos = mul(UNITY_MATRIX_I_VP, ndc);
                worldPos /= worldPos.w;
                
                return worldPos;
            }

            v2f vert (appdata vsIn)
            {
                v2f vsOut;
                vsOut.vertex = TransformObjectToHClip(vsIn.vertex.xyz);
                vsOut.uv = vsIn.uv;
                return vsOut;
            }

            float4 frag (v2f psIn) : SV_Target
            {
                float4 color = float4(0, 0, 0, 1);

                float4 worldPos = GetFragmentWorldPos(psIn.uv);
                float3 albedo = SAMPLE_TEXTURE2D_X_LOD(_GBuffer0, sampler_point_clamp, psIn.uv, 0).xyz;
                float3 normal = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, sampler_point_clamp, psIn.uv, 0).xyz;

                float3 gi = SampleSHVoxel(worldPos, albedo, normal, _CoefficientVoxel, _CoefficientVoxelSize, _CoefficientVoxelCorner, _CoefficientVoxelGridSize);
                color.rgb += gi * _GIIntensity;

                return color;
            }
            
            ENDHLSL
        }
    }
}