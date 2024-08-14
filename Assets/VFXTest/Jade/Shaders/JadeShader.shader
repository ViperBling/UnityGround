Shader "VFXTest/JadeShader"
{
    Properties
    {
        [HDR]_MainColor ("Main Color", Color) = (1, 1, 1, 1)
        _MainTex ("Main Texture", 2D) = "white" {}
        _NormalMap ("Normal Texture", 2D) = "bump" {}
        _GeoMap ("Geometry Map", 2D) = "white" {}
        _ParallaxMap ("Parallax Map", 2D) = "white" {}
        
        [Space]
        [Header(SSS)]
        _ScatterAmount ("Scatter Amount", Color) = (1, 1, 1, 1)
        
        [Space]
        [Header(Lighting)]
        [HDR]_EdgeColor ("Edge Color", Color) = (1, 1, 1, 1)
        [HDR]_SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        _Shininess ("_Shininess", Range(0.01, 100)) = 1
        _Roughness ("Roughness", Range(0.01, 1)) = 0.5
        // _WrapValue ("Wrap Value", Range(0, 1)) = 0.5
        _FresnelPow ("Fresnel Power", Float) = 1
        _ReflectCubeIntensity ("Reflect Cube Intensity", Float) = 1.0
        
        [Space]
        [Header(BackLighting)]
        [HDR]_BackLightColor ("BackLight Color", Color) = (1, 1, 1, 1)
        _BackDistortion ("Back Distortion", Range(0.0, 2)) = 0.5
        _BackPower ("Back Power", Float) = 1
        _BackScale ("Back Scale", Float) = 1
        _ThicknessScale ("ThicknessPower", Float) = 1
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
        #include "Assets/VFXTest/Jade/Shaders/SG.hlsl"
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);      SAMPLER(sampler_NormalMap);
            TEXTURE2D(_GeoMap);         SAMPLER(sampler_GeoMap);
            TEXTURE2D(_ParallaxMap);    SAMPLER(sampler_ParallaxMap);
            // TEXTURE2D(_CameraOpaqueTexture);       SAMPLER(sampler_CameraOpaqueTexture);

            CBUFFER_START(UnityPerMaterial)
            half4 _MainColor;
            float4 _ParallaxMap_ST;
            half4 _ScatterAmount;
            half4 _EdgeColor;
            half4 _SpecularColor;
            half _Shininess;
            half _Roughness;
            half _WrapValue;
            half _FresnelPow;
            half _ReflectCubeIntensity;
            half4 _BackLightColor;
            half _BackDistortion;
            half _BackPower;
            half _BackScale;
            half _ThicknessScale;
            CBUFFER_END
            
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

            float3 WorldNormal(float3 tSpace0, float3 tSpace1, float3 tSpace2, float3 normal)
            {
                return normalize(float3(dot(tSpace0.xyz, normal), dot(tSpace1.xyz, normal), dot(tSpace2.xyz, normal)));
            }

            half GGXMobile(half roughness, float NoH)
            {
                float OneMinusNoHSqr = 1.0 - NoH * NoH; 
	            half a = roughness * roughness;
	            half n = NoH * a;
	            half p = a / (OneMinusNoHSqr + n * n);
	            half d = p * p;
	            // clamp to avoid overlfow in a bright env
	            return min(d, 2048.0);
            }

            half CalcSpecular(half roughness, half NoH, half HoL)
            {
            	return (roughness * 0.25 + 0.25) * GGXMobile(roughness, NoH);
            }

            Varyings VertexPass (Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;
                
                vsOut.positionCS = TransformObjectToHClip(vsIn.positionOS.xyz);
                vsOut.texCoord = TRANSFORM_TEX(vsIn.texCoord, _ParallaxMap);
                // vsOut.texCoord = vsIn.texCoord;
                float3 positionWS = TransformObjectToWorld(vsIn.positionOS);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(vsIn.normalOS);
                vsOut.tSpace0 = float4(normalInputs.tangentWS.x, normalInputs.bitangentWS.x, normalInputs.normalWS.x, positionWS.x);
                vsOut.tSpace1 = float4(normalInputs.tangentWS.y, normalInputs.bitangentWS.y, normalInputs.normalWS.y, positionWS.y);
                vsOut.tSpace2 = float4(normalInputs.tangentWS.z, normalInputs.bitangentWS.z, normalInputs.normalWS.z, positionWS.z);
                
                return vsOut;
            }

            half4 FragmentPass (Varyings fsIn) : SV_Target
            {
                Light mainLight = GetMainLight();
                half3 lightDir = normalize(mainLight.direction);
                half3 lightColor = mainLight.color;
                half shadowAtten = mainLight.shadowAttenuation;
                half distanceAtten = mainLight.distanceAttenuation;
                
                float3 positionWS = float3(fsIn.tSpace0.w, fsIn.tSpace1.w, fsIn.tSpace2.w);
                half3 vertexNormalWS = normalize(float3(fsIn.tSpace0.z, fsIn.tSpace1.z, fsIn.tSpace2.z));
                half3 viewDir = -normalize(positionWS - _WorldSpaceCameraPos);

                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);
                half3 baseColor = mainTex.rgb * _MainColor.rgb;
                half4 parallaxTex = SAMPLE_TEXTURE2D(_ParallaxMap, sampler_ParallaxMap, fsIn.texCoord);
                half4 normalTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, fsIn.texCoord);
                half4 geoTex = SAMPLE_TEXTURE2D(_GeoMap, sampler_GeoMap, fsIn.texCoord);
                half ao = geoTex.r;
                half thickness = (1 - geoTex.g) * _ThicknessScale;

                half3 normalTS = UnpackNormalScale(normalTex, 1.0);
                half3 normalWS = WorldNormal(fsIn.tSpace0.xyz, fsIn.tSpace1.xyz, fsIn.tSpace2.xyz, normalTS);

                half3 halfDir = normalize(lightDir + viewDir);
                half NoH = saturate(dot(normalWS, halfDir));
                half NoL = saturate(dot(normalWS, lightDir));
                half NoV = saturate(dot(normalWS, viewDir));
                half HoL = saturate(dot(halfDir, lightDir));

                // ============= SSS
                half3 scatter = (1 - parallaxTex.r) * baseColor;
                half3 sg = SGDiffuseLighting(normalWS, lightDir, scatter);

                // ============= BackLight
                half3 backLightDir = -normalize(lightDir + normalWS * _BackDistortion);
                half VoL = saturate(dot(viewDir, backLightDir));
                half backLightTerm = pow(VoL, _BackPower) * _BackScale;
                half3 backColor = backLightTerm * thickness * _BackLightColor.rgb;

                // ============= Diffuse
                // half3 wrapDiffuse = max(0, (NoL + _WrapValue) / (1 + _WrapValue));
                // half3 diffuse = _MainColor.rgb * wrapDiffuse * _MainLightColor.rgb;
                half3 diffuse = distanceAtten * sg * baseColor;
                
                // ============= Specular
                // half3 specular = lightColor * _SpecularColor.rgb * pow(NoH, _Shininess);
                half3 specular = _SpecularColor.rgb * CalcSpecular(_Roughness, NoH, HoL) * NoL * lightColor * mainTex.rgb;
                
                // ============= EnvLight
                half3 reflectDir = normalize(reflect(-viewDir, normalWS));
                half3 indirectDiffuse = SampleSH(normalWS) * mainTex.rgb * _MainColor.rgb;
                half3 indirectSpecular = GlossyEnvironmentReflection(reflectDir, _Roughness, ao) * _SpecularColor.rgb * _ReflectCubeIntensity;
                half3 GIData = indirectDiffuse + indirectSpecular;

                // ============= Final Tune
                half3 finalColor = backColor + diffuse + specular + GIData;
                half3 fresnelTrem = pow(1 - NoV, _FresnelPow);
                // finalColor = lerp(finalColor, _MainColor.rgb, fresnelTrem);
                finalColor += fresnelTrem * _EdgeColor.rgb;
                
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Universal Pipeline keywords

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            // This is used during shadow map generation to differentiate between directional and punctual light shadows, as they use different formulas to apply Normal Bias
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}
