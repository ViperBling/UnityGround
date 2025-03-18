Shader "InstancedGrass/MeshGrass"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" { }
        _TopColor ("Top Color", Color) = (1, 1, 1, 1)
        _BottomColor ("Bottom Color", Color) = (1, 1, 1, 1)
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
            Cull Back
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

            TEXTURE2D(_MainTex);    SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _TopColor;
                half4 _BottomColor;
                StructuredBuffer<float3> _InstancePositionBuffer;
                StructuredBuffer<uint> _VisibleInstanceIndexBuffer;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 texCoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texCoord : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : NORMAL;
                float3 color : COLOR;
            };

            Varyings VertexPass(Attributes vsIn, uint instanceID : SV_InstanceID)
            {
                Varyings vsOut = (Varyings)0;
                float3 perGrassPivotPosWS = _InstancePositionBuffer[_VisibleInstanceIndexBuffer[instanceID]];

                float3 cameraTransformRightWS = UNITY_MATRIX_V[0].xyz;          //UNITY_MATRIX_V[0].xyz == world space camera Right unit vector
                float3 cameraTransformUpWS = UNITY_MATRIX_V[1].xyz;             //UNITY_MATRIX_V[1].xyz == world space camera Up unit vector
                float3 cameraTransformForwardWS = -UNITY_MATRIX_V[2].xyz;       //UNITY_MATRIX_V[2].xyz == -1 * world space camera Forward unit vector

                // float3 positionOS = vsIn.positionOS.x * cameraTransformRightWS * (sin(perGrassPivotPosWS.x * 95.4643 + perGrassPivotPosWS.z) * 0.45 + 0.55);    //random w
                // positionOS += vsIn.positionOS.y * cameraTransformUpWS;

                // 使用实例位置作为随机种子生成伪随机值
                float randomVal1 = frac(sin(dot(perGrassPivotPosWS.xz, float2(12.9898, 78.233))) * 43758.5453);
                float randomVal2 = frac(sin(dot(perGrassPivotPosWS.xz, float2(39.3465, 27.9135))) * 34159.2531);
                float randomVal3 = frac(sin(dot(perGrassPivotPosWS.xz, float2(73.1573, 52.5329))) * 37526.2371);
                
                // 随机旋转角度 (0-2π)
                float randomRotation = randomVal1 * TWO_PI;
                
                // 随机缩放 (0.8-1.2)
                float randomScale = lerp(0.8, 1.2, randomVal2);
                
                // 随机倾斜量
                float randomTilt = lerp(-0.2, 0.2, randomVal3);
                
                // 构建旋转矩阵 (Y轴旋转)
                float sinR = sin(randomRotation);
                float cosR = cos(randomRotation);
                float3x3 rotationMatrix = float3x3(
                    cosR, 0, sinR,
                    0, 1, 0,
                    - sinR, 0, cosR
                );
                
                // 构建倾斜矩阵 (沿着XZ平面随机倾斜)
                float3x3 tiltMatrix = float3x3(
                    1, 0, randomTilt,
                    0, 1, randomTilt,
                    0, 0, 1
                );
                
                // 应用变换: 先缩放，再旋转，再倾斜
                float3 transformedPos = vsIn.positionOS.xyz * randomScale;
                transformedPos = mul(rotationMatrix, transformedPos);
                transformedPos = mul(tiltMatrix, transformedPos);

                float3 positionWS = transformedPos + perGrassPivotPosWS;

                vsOut.positionCS = TransformWorldToHClip(positionWS);
                vsOut.texCoord = vsIn.texCoord;
                vsOut.normalWS = TransformObjectToWorldNormal(vsIn.normalOS);
                vsOut.positionWS = positionWS;
                vsOut.color = positionWS.xyz;
                return vsOut;
            }

            float4 FragmentPass(Varyings fsIn) : SV_Target
            {
                half4 mainTexVal = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);
                half grassRamp = mainTexVal.g;

                clip(mainTexVal.r - 0.5);

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(fsIn.positionWS));

                half NoL = max(0.0, dot(mainLight.direction, fsIn.normalWS));

                half3 finalColor = lerp(_BottomColor.rgb, _TopColor.rgb, mainTexVal.g);
                
                finalColor = NoL;
                // float fogFactor = ComputeFogFactor(fsIn.positionCS.z);
                // finalColor = MixFog(finalColor, fogFactor);

                return float4(finalColor.xyz, 1.0);
            }

            ENDHLSL
        }
    }
}
