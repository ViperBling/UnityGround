Shader "InstancedGrass/MeshGrass"
{
    Properties
    {
        [Header(BaseSettings)]
        _MainTex ("Texture", 2D) = "white" { }
        _ColorBlendingTex ("Color Blending", 2D) = "white" { }
        _GrassTopColor ("Top Color", Color) = (1, 1, 1, 1)
        _GrassBottomColor ("Bottom Color", Color) = (1, 1, 1, 1)
        _GrassBaseColor ("Grass Base Color", Color) = (1, 1, 1, 1)

        [Header(LightingSettings)]
        _RandomNormal ("Random Normal", Range(-1, 1)) = 0.1
        _WrapValue ("Wrap Value", Range(0, 1)) = 0.5
        _SpecularShininess ("Specular Shininess", Range(0, 100)) = 50
        _SpecularIntensity ("Specular Intensity", Range(0, 10)) = 1

        [Header(WindSettings)]
        _WindNoiseTexture ("Wind Noise Texture", 2D) = "white" { }
        _WindNoiseParam ("Wind Noise Parameters", Vector) = (1, 1, 0, 0)
        _WindBending ("Wind Bending", Vector) = (0.1, 1.0, 0, 0)
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
            // #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            // #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            // #pragma multi_compile _ _SHADOWS_SOFT
            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fog

            #include "Assets/InstancedGrass/Shaders/InstancedGrassCommon.hlsl"

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
                float randomScale = lerp(0.7, 1.4, randomVal2);
                
                // 随机倾斜量
                float randomTilt = lerp(-0.1, 0.1, randomVal3);
                
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

                half windDistortion = SAMPLE_TEXTURE2D_LOD(_ColorBlendingTex, sampler_ColorBlendingTex, positionWS.xz * 0.01, 0.0).r;
                float2 windUV = positionWS.xz * _WindTilling + _Time.y * _WindIntensity + windDistortion;
                // 顶点着色器内采样贴图，必须使用SAMPLE_TEXTURE_LOD函数，否则会报错
                float wind = SAMPLE_TEXTURE2D_LOD(_WindNoiseTexture, sampler_WindNoiseTexture, windUV, 0).r;
                wind *= Smootherstep(_WindBendingLow, _WindBendingHigh, vsIn.positionOS.y);

                // float3 windOffset = cameraTransformRightWS * wind; //swing using billboard left right direction
                positionWS.xyz += wind;

                half3 randomAddToN = (_RandomNormal * sin(perGrassPivotPosWS.x * 82.32523 + perGrassPivotPosWS.z) + wind * - 0.25) * cameraTransformRightWS;
                half3 flattenNormal = normalize(half3(0, 1, 0) + randomAddToN - cameraTransformForwardWS * 0.5);
                half3 normalWS = /* TransformObjectToWorldNormal(vsIn.normalOS) */flattenNormal;
                // normalWS = BlendNormalWorldspaceRNM(flattenNormal, normalWS, vsIn.normalOS.xyz);
                // normalWS = flattenNormal;

                vsOut.positionCS = TransformWorldToHClip(positionWS);
                vsOut.texCoord = vsIn.texCoord;
                vsOut.positionWS = positionWS;
                vsOut.positionOS = vsIn.positionOS.xyz;
                vsOut.perGrassPivotPosWS = perGrassPivotPosWS;
                vsOut.normalWS = normalWS;
                return vsOut;
            }

            float4 FragmentPass(Varyings fsIn) : SV_Target
            {
                half4 mainTexVal = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);
                clip(mainTexVal.r - 0.5);

                half grassRamp = mainTexVal.g;
                float3 perGrassPivotPosWS = fsIn.perGrassPivotPosWS;

                float3 cameraTransformRightWS = UNITY_MATRIX_V[0].xyz;          //UNITY_MATRIX_V[0].xyz == world space camera Right unit vector
                float3 cameraTransformUpWS = UNITY_MATRIX_V[1].xyz;             //UNITY_MATRIX_V[1].xyz == world space camera Up unit vector
                float3 cameraTransformForwardWS = -UNITY_MATRIX_V[2].xyz;       //UNITY_MATRIX_V[2].xyz == -1 * world space camera Forward unit vector

                half colorRamp = fsIn.texCoord.y;

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(fsIn.positionWS));
                half3 lightDir = mainLight.direction;
                half3 lightColor = mainLight.color.rgb;
                half attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                half3 lighting = lightColor * attenuation;

                half3 albedo = lerp(_GrassBottomColor.rgb, _GrassTopColor.rgb, grassRamp);
                float2 blendingUV = fsIn.positionWS.xz * 0.1;
                half colorBlending = SAMPLE_TEXTURE2D(_ColorBlendingTex, sampler_ColorBlendingTex, blendingUV).r;
                albedo = lerp(albedo, _GrassBaseColor.rgb, colorBlending * colorRamp);
                
                half3 normalWS = fsIn.normalWS;
                half3 viewDirWS = normalize(_WorldSpaceCameraPos - fsIn.positionWS);

                half3 color = SimpleLit(albedo, normalWS, viewDirWS, lightDir, lightColor, attenuation, colorRamp);
                // half3 color = StylizedGrassLit(
                //     albedo, normalWS, viewDirWS, lightDir, lighting, colorRamp,
                //     0.05, colorRamp
                // );

                half3 finalColor = color;

                return float4(finalColor.xyz, 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            // -------------------------------------
            // Render State Commands
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}
