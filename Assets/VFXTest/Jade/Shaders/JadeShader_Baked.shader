Shader "VFXTest/JadeShader_Baked"
{
    Properties
    {
        [HDR]_MainColor ("Main Color", Color) = (1, 1, 1, 1)
        _MainTex ("Main Texture", 2D) = "white" {}
        _NormalMap ("Normal Texture", 2D) = "bump" {}
        _GeoMap ("Geometry Map", 2D) = "white" {}
        _DistortionMap ("Distortion Map", 2D) = "white" {}
        _ParallaxMap ("Parallax Map", 2D) = "white" {}
        [HDR]_InnerColor ("Inner Color", Color) = (1, 1, 1, 1)
        _RefractPower ("Refract Power", Float) = 1
        _RefractIntensity ("Refract Intensity", Float) = 1
        _InnerDepth ("Inner Depth", Float) = 10
        
        [Space]
        [Header(SSS)]
        _ScatterAmount ("Scatter Amount", Color) = (1, 1, 1, 1)
        
        [Space]
        [Header(Lighting)]
        [HDR]_EdgeColor ("Edge Color", Color) = (1, 1, 1, 1)
        [HDR]_SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        // _Shininess ("_Shininess", Range(0.01, 100)) = 1
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
        _Sharpness ("Thickness Sharpness", Float) = 1
        _ThicknessScale ("ThicknessScale", Float) = 1
        _ThicknessPower ("ThicknessPower", Float) = 1
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
            TEXTURE2D(_DistortionMap);     SAMPLER(sampler_DistortionMap);
            TEXTURE2D(_ParallaxMap);    SAMPLER(sampler_ParallaxMap);
            // TEXTURE2D(_CameraOpaqueTexture);       SAMPLER(sampler_CameraOpaqueTexture);

            CBUFFER_START(UnityPerMaterial)
            half4 _MainColor;
            float4 _MainTex_ST;
            float4 _DistortionMap_ST;
            float4 _ParallaxMap_ST;
            half4 _InnerColor;
            half _RefractPower;
            half _RefractIntensity;
            half _InnerDepth;
            half4 _ScatterAmount;
            half _Sharpness;
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
            half _ThicknessPower;
            CBUFFER_END
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                half3 normalOS    : NORMAL;
                half4 vertexColor : COLOR;
                float2 texCoord   : TEXCOORD0;
                float2 texCoord2  : TEXCOORD1;
                float2 texCoord3  : TEXCOORD2;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texCoord   : TEXCOORD0;
                float4 tSpace0    : TEXCOORD1;
                float4 tSpace1    : TEXCOORD2;
                float4 tSpace2    : TEXCOORD3;
                half3  viewDirWS  : TEXCOORD4;
                half3  viewDirTS  : TEXCOORD5;
                half   thickness  : TEXCOORD6;
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
                vsOut.texCoord = TRANSFORM_TEX(vsIn.texCoord, _MainTex);
                // vsOut.texCoord = vsIn.texCoord;
                float3 positionWS = TransformObjectToWorld(vsIn.positionOS);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(vsIn.normalOS);
                vsOut.tSpace0 = float4(normalInputs.tangentWS.x, normalInputs.bitangentWS.x, normalInputs.normalWS.x, positionWS.x);
                vsOut.tSpace1 = float4(normalInputs.tangentWS.y, normalInputs.bitangentWS.y, normalInputs.normalWS.y, positionWS.y);
                vsOut.tSpace2 = float4(normalInputs.tangentWS.z, normalInputs.bitangentWS.z, normalInputs.normalWS.z, positionWS.z);

                float3x3 TBN = float3x3(normalInputs.tangentWS.xyz, normalInputs.bitangentWS.xyz, normalInputs.normalWS.xyz);

                vsOut.viewDirWS = normalize(_WorldSpaceCameraPos - positionWS);
                vsOut.viewDirTS = normalize(mul(TBN, vsOut.viewDirWS));
                
                float4 meanRayAndReverseDist = float4(vsIn.texCoord2.xy, vsIn.texCoord3.xy);
                float3 meanRay = meanRayAndReverseDist.xyz * 2.0 - 1.0;
                meanRay = TransformObjectToWorldDir(meanRay);
                // float meanDist = 1.0 / meanRayAndReverseDist.w;
                float meanDist = meanRayAndReverseDist.w;
                half MoV = dot(vsOut.viewDirWS, meanRay);
                vsOut.thickness = exp(_Sharpness * (MoV - 1.0)) * meanDist - 0.5;
                // vsOut.thickness = pow(MoV * 0.5 + 0.5, _Sharpness) * meanDist - 0.5;
                
                return vsOut;
            }

            half4 FragmentPass (Varyings fsIn) : SV_Target
            {
                Light mainLight = GetMainLight();
                half3 lightDir = normalize(mainLight.direction);
                half3 lightColor = mainLight.color;
                half shadowAtten = mainLight.shadowAttenuation;
                half distanceAtten = mainLight.distanceAttenuation;
                
                half3 viewDirWS = fsIn.viewDirWS;
                half3 viewDirTS = fsIn.viewDirTS;

                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord);
                half3 baseColor = mainTex.rgb * _MainColor.rgb;
                half4 normalTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, fsIn.texCoord);
                half4 geoTex = SAMPLE_TEXTURE2D(_GeoMap, sampler_GeoMap, fsIn.texCoord);
                half ao = geoTex.r;
                // half thickness = saturate(pow(1 - geoTex.g, _ThicknessPower)) * _ThicknessScale;
                half thickness = saturate(pow(fsIn.thickness, _ThicknessPower) * _ThicknessScale);

                half3 normalTS = UnpackNormalScale(normalTex, 1.0);
                half3 normalWS = WorldNormal(fsIn.tSpace0.xyz, fsIn.tSpace1.xyz, fsIn.tSpace2.xyz, normalTS);

                half3 halfDir = normalize(lightDir + viewDirWS);
                half NoH = saturate(dot(normalWS, halfDir));
                half NoL = saturate(dot(normalWS, lightDir));
                half NoV = saturate(dot(normalWS, viewDirWS));
                half HoL = saturate(dot(halfDir, lightDir));

                // ============= Inner Albedo
                half3 reflectDirTS = reflect(-viewDirTS, half3(0, 0, 1));
                float depth = _InnerDepth / abs(reflectDirTS.z);
                float2 uvOffset = reflectDirTS.xy * depth / 1024;
                half2 distortionTEX = SAMPLE_TEXTURE2D(_DistortionMap, sampler_DistortionMap, fsIn.texCoord * _DistortionMap_ST.xy + _DistortionMap_ST.zw).rg;
                float2 refractUV = distortionTEX * _ParallaxMap_ST.xy + _ParallaxMap_ST.zw + uvOffset;
                half3 refractColor = SAMPLE_TEXTURE2D(_ParallaxMap, sampler_ParallaxMap, refractUV).rgb;
                refractColor = pow(refractColor, _RefractPower) * _RefractIntensity;

                // ============= SSS & Diffuse
                half3 scatter = _ScatterAmount.rgb;
                half3 sg = SGDiffuseLighting(normalWS, lightDir, scatter);
                // half3 wrapDiffuse = max(0, (NoL + _WrapValue) / (1 + _WrapValue));
                // half3 diffuse = _MainColor.rgb * wrapDiffuse * _MainLightColor.rgb;
                half3 diffuse = distanceAtten * sg;

                // ============= Specular
                // half3 specular = lightColor * _SpecularColor.rgb * pow(NoH, _Shininess);
                half3 specular = _SpecularColor.rgb * CalcSpecular(_Roughness, NoH, HoL) * NoL * lightColor;

                // ============= BackLight
                half3 backLightDir = -normalize(lightDir + normalWS * _BackDistortion);
                half VoL = saturate(dot(viewDirWS, backLightDir));
                half backLightTerm = pow(VoL, _BackPower) * _BackScale;
                half3 backColor = backLightTerm * thickness * _BackLightColor.rgb * refractColor;
                
                // ============= EnvLight
                half3 reflectDir = normalize(reflect(-viewDirWS, normalWS));
                half3 indirectDiffuse = SampleSH(normalWS) * ao;
                half3 indirectSpecular = GlossyEnvironmentReflection(reflectDir, _Roughness, ao) * _SpecularColor.rgb * _ReflectCubeIntensity;
                half3 GIData = indirectDiffuse + indirectSpecular;

                // ============= Final Tune
                half3 finalColor = backColor + baseColor * (diffuse + specular + GIData) + refractColor * _InnerColor.rgb;
                half fresnelTrem = pow(1 - NoV, _FresnelPow);
                finalColor = lerp(finalColor, _EdgeColor.rgb, fresnelTrem * thickness);
                // finalColor += fresnelTrem * _EdgeColor.rgb;

                // Fast ToneMap
                finalColor = saturate((finalColor * (2.51 * finalColor + 0.03)) / (finalColor * (2.43 * finalColor + 0.59) + 0.14));
                
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
