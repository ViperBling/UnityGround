Shader "VFXTest/JadeShader_Baked_SH_H"
{
    Properties
    {
        [Header(Main)]
        [HDR]_MainColor ("Main Color", Color) = (1, 1, 1, 1)
        _MainTex ("Main Texture", 2D) = "white" {}
        _NormalMap ("Normal Texture", 2D) = "bump" {}
        // _DistortionMap ("Distortion Map", 2D) = "white" {}
        _ParallaxMap ("Parallax Map", 2D) = "white" {}
        [Toggle(USE_COMPUTE_UV)] _UseComputeUV ("Use Compute UV", Int) = 0
        [HDR]_InnerColor ("Inner Color", Color) = (1, 1, 1, 1)
        _RefractPower ("Refract Power", Float) = 1
        _RefractIntensity ("Refract Intensity", Float) = 1
        _InnerDepth ("Inner Depth", Float) = 10
        
        [Space]
        [Header(SSS)]
        _ScatterAmount ("Scatter Amount", Color) = (1, 1, 1, 1)
        _ThicknessSharpness ("Thickness Sharpness", Float) = 1
        _ThicknessScale ("ThicknessScale", Float) = 1
        _ThicknessPower ("ThicknessPower", Float) = 1
        
        [Space]
        [Header(Lighting)]
        [HDR]_EdgeColor ("Edge Color", Color) = (1, 1, 1, 1)
        [HDR]_SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        // _Shininess ("_Shininess", Range(0.01, 100)) = 1
        _Roughness ("Roughness", Range(0.01, 1)) = 0.5
        _BumpScale ("Bump Scale", Float) = 1
        _WrapValue ("Wrap Value", Range(0, 1)) = 0.5
        // _FresnelPow ("Fresnel Power", Float) = 1
        _ReflectCubeIntensity ("Reflect Cube Intensity", Float) = 1.0
        
        [Space]
        [Header(BackLighting)]
        [HDR]_BackLightColor ("BackLight Color", Color) = (1, 1, 1, 1)
        _BackDistortion ("Back Distortion", Range(0.0, 2)) = 0.5
        _BackPower ("Back Power", Float) = 1
        _BackScale ("Back Scale", Float) = 1
    }
    
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
        #include "SG.hlsl"
        ENDHLSL

        Pass
        {
            Tags
            {
                "RenderPipeline" = "UniversalPipeline"
            }
            
            HLSLPROGRAM
            #pragma shader_feature _ USE_COMPUTE_UV
            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);      SAMPLER(sampler_NormalMap);
            // TEXTURE2D(_DistortionMap);  SAMPLER(sampler_DistortionMap);
            TEXTURE2D(_ParallaxMap);    SAMPLER(sampler_ParallaxMap);

            CBUFFER_START(UnityPerMaterial)
                half4   _MainColor;
                float4  _MainTex_ST;
                float4  _DistortionMap_ST;
                float4  _ParallaxMap_ST;
                half4   _InnerColor;
                half    _RefractPower;
                half    _RefractIntensity;
                half    _InnerDepth;
                half4   _ScatterAmount;
                half    _ThicknessSharpness;
                half4   _EdgeColor;
                half4   _SpecularColor;
                half    _Shininess;
                half    _Roughness;
                half    _BumpScale;
                half    _WrapValue;
                half    _ReflectCubeIntensity;
                half4   _BackLightColor;
                half    _BackDistortion;
                half    _BackPower;
                half    _BackScale;
                half    _ThicknessScale;
                half    _ThicknessPower;
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
                float4 texCoord   : TEXCOORD0;
                float4 tSpace0    : TEXCOORD1;
                float4 tSpace1    : TEXCOORD2;
                float4 tSpace2    : TEXCOORD3;
                half3  viewDirWS  : TEXCOORD4;
                half3  viewDirTS  : TEXCOORD5;
                half   thickness  : TEXCOORD6;
                // half thicknessLS  : TEXCOORD7;
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
	            // Clamp to avoid overlfow in a bright env
	            return min(d, 2048.0);
            }

            half CalcSpecular(half roughness, half NoH)
            {
            	return (roughness * 0.25 + 0.25) * GGXMobile(roughness, NoH);
            }

            Varyings VertexPass (Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;
                
                vsOut.positionCS = TransformObjectToHClip(vsIn.positionOS.xyz);
                vsOut.texCoord.xy = TRANSFORM_TEX(vsIn.texCoord, _MainTex);
                // vsOut.texCoord = vsIn.texCoord;
                float3 positionWS = TransformObjectToWorld(vsIn.positionOS.xyz);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(vsIn.normalOS);
                vsOut.tSpace0 = float4(normalInputs.tangentWS.x, normalInputs.bitangentWS.x, normalInputs.normalWS.x, positionWS.x);
                vsOut.tSpace1 = float4(normalInputs.tangentWS.y, normalInputs.bitangentWS.y, normalInputs.normalWS.y, positionWS.y);
                vsOut.tSpace2 = float4(normalInputs.tangentWS.z, normalInputs.bitangentWS.z, normalInputs.normalWS.z, positionWS.z);

                float3x3 TBN = float3x3(normalInputs.tangentWS.xyz, normalInputs.bitangentWS.xyz, normalInputs.normalWS.xyz);

                vsOut.viewDirWS = normalize(_WorldSpaceCameraPos - positionWS);
                vsOut.viewDirTS = normalize(mul(TBN, vsOut.viewDirWS));
                half3 viewDirOS = -TransformWorldToObjectDir(vsOut.viewDirWS);

                // half3 lightDir = GetMainLight().direction;

                half4 coff = half4(vsIn.texCoord2.xy, vsIn.texCoord3.xy);
                half sphereCoff = sqrt(3.0 / (4.0 * PI));
                half Y0 = 1.0 / 2.0 * sqrt(1.0 / PI);
                half Y1 = sphereCoff * viewDirOS.z;
                half Y2 = sphereCoff * viewDirOS.y;
                half Y3 = sphereCoff * viewDirOS.x;
                half dist = coff.x * Y0 + coff.y * Y1 + coff.z * Y2 + coff.w * Y3;
                vsOut.thickness = exp(-dist * dist * _ThicknessSharpness * 0.1);

                #if defined(USE_COMPUTE_UV)
                half3 leftDirectionOS = TransformWorldToObjectDir(half3(1, 0, 0));
                half3 upDirectionOS = TransformWorldToObjectDir(half3(0, 1, 0));
                float u = dot(vsIn.positionOS.xyz, leftDirectionOS);
                float v = dot(vsIn.positionOS.xyz, upDirectionOS);
                vsOut.texCoord.zw = float2(u, v) * _ParallaxMap_ST.xy + _ParallaxMap_ST.zw;
                #else
                vsOut.texCoord.zw = vsIn.texCoord.xy * _ParallaxMap_ST.xy + _ParallaxMap_ST.zw;
                #endif

                // Light space thickness for better diffuse.
                // half Y1LS =  sphereCoff * lightDir.z;
                // half Y2LS =  sphereCoff * lightDir.y;
                // half Y3LS = -sphereCoff * lightDir.x;
                // half distLS = coff.x * Y0 + coff.y * Y1LS + coff.z * Y2LS + coff.w * Y3LS;
                // vsOut.thicknessLS = exp(-distLS * distLS * _Sharpness * 0.1);
                
                return vsOut;
            }

            half4 FragmentPass (Varyings fsIn) : SV_Target
            {
                Light mainLight = GetMainLight();
                half3 lightDir = normalize(mainLight.direction);
                half3 lightColor = mainLight.color;
                half shadowAtten = mainLight.shadowAttenuation;
                half distanceAtten = mainLight.distanceAttenuation;
                
                // float3 positionWS = float3(fsIn.tSpace0.w, fsIn.tSpace1.w, fsIn.tSpace2.w);
                // half3 vertexNormalWS = normalize(float3(fsIn.tSpace0.z, fsIn.tSpace1.z, fsIn.tSpace2.z));
                half3 viewDirWS = fsIn.viewDirWS;
                half3 viewDirTS = fsIn.viewDirTS;

                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, fsIn.texCoord.xy);
                half3 baseColor = mainTex.rgb * _MainColor.rgb;
                half4 normalTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, fsIn.texCoord.xy);
                half ao = normalTex.a;
                half thickness = saturate(pow(saturate(fsIn.thickness), _ThicknessPower) * _ThicknessScale);

                half3 normalTS = UnpackNormalRGB(normalTex, _BumpScale);
                half3 normalWS = WorldNormal(fsIn.tSpace0.xyz, fsIn.tSpace1.xyz, fsIn.tSpace2.xyz, normalTS);
                half3 normalVS = TransformWorldToViewDir(normalWS);

                half3 halfDir = normalize(lightDir + viewDirWS);
                half NoH = saturate(dot(normalWS, halfDir));
                half NoL = saturate(dot(normalWS, lightDir));
                // half NoV = saturate(dot(normalWS, viewDirWS));

                // ============= Inner Albedo
                half3 reflectDirTS = reflect(-viewDirTS, half3(0, 0, 1));
                float depth = _InnerDepth / abs(reflectDirTS.z);
                float2 uvOffset = reflectDirTS.xy * depth / 1024;
                // half2 distortionTEX = SAMPLE_TEXTURE2D(_DistortionMap, sampler_DistortionMap, fsIn.texCoord * _DistortionMap_ST.xy + _DistortionMap_ST.zw + uvOffset).rg;
                // float2 refractUV = distortionTEX * _ParallaxMap_ST.xy + _ParallaxMap_ST.zw;
                float2 refractUV = fsIn.texCoord.zw + normalVS.xy * 0.01 + uvOffset;
                half refractColor = SAMPLE_TEXTURE2D(_ParallaxMap, sampler_ParallaxMap, refractUV).r;
                refractColor = pow(refractColor, _RefractPower) * _RefractIntensity;

                // ============= SSS & Diffuse
                half3 scatter = _ScatterAmount.rgb;
                half3 sg = SGDiffuseLighting(normalWS, lightDir, scatter);
                // half3 wrapDiffuse = max(0, (NoL + _WrapValue) / (1 + _WrapValue));
                // half3 diffuse = wrapDiffuse * baseColor;
                half3 diffuse = shadowAtten * distanceAtten * sg;

                // ============= Specular
                half3 specular = _SpecularColor.rgb * CalcSpecular(_Roughness, NoH) * lightColor * NoL;

                // ============= BackLight
                half3 backLightDir = -normalize(lightDir + normalWS * _BackDistortion);
                half VoL = saturate(dot(viewDirWS, backLightDir));
                half backLightTerm = pow(VoL, _BackPower) * _BackScale;
                half3 backColor = backLightTerm * thickness * _BackLightColor.rgb * lightColor;
                
                // ============= EnvLight
                half3 reflectDir = normalize(reflect(-viewDirWS, normalWS));
                half3 indirectDiffuse = SampleSH(normalWS) * ao;
                half3 indirectSpecular = GlossyEnvironmentReflection(reflectDir, _Roughness, ao) * _SpecularColor.rgb * _ReflectCubeIntensity;
                half3 GIData = indirectDiffuse + indirectSpecular;

                // ============= Final Tune
                half3 finalColor = diffuse + specular + GIData;
                finalColor = mainTex.rgb * lerp(_MainColor.rgb * finalColor, _EdgeColor.rgb, thickness) + backColor;
                finalColor = lerp(finalColor, _InnerColor.rgb, refractColor);
                finalColor = lerp(finalColor, specular, _Roughness);

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
            Cull Back

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
