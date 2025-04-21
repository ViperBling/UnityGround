Shader "VFXTest/DistortionWings"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" { }

        [HDR]_Color01 ("Color01", Color) = (1, 1, 1, 1)
        [HDR]_Color02 ("Color02", Color) = (1, 1, 1, 1)
        [HDR]_Color03 ("Color03", Color) = (1, 1, 1, 1)
        [HDR]_Color04 ("Color04", Color) = (1, 1, 1, 1)
        _DistortionNoise ("Distortion Noise", 2D) = "white" { }
        _DistortionScale ("Distortion Scale", Vector) = (1, 1, 0, 0)
        _WavedNoise ("Waved Noise", 2D) = "white" { }

        _EdgeWidth ("Edge Width", Range(0, 10)) = 0.5
        _EdgeSoftFactor ("Edge Width Controll", Range(0, 10)) = 0.5
        _EdgeFactor ("Edge Factor", Range(0, 10)) = 0.5
        _Mask01Exp ("Mask01 Exp", Range(0, 10)) = 1

        _GradientThresholds ("Gradient Thresholds (x,y,z,w)", Vector) = (0.25, 0.5, 0.75, 1.0)
        _GradientSmoothness ("Gradient Smoothness", Range(0.001, 10)) = 0.1
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }

        Pass
        {
            Name "Wings Effect"

            // Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma vertex VertexPass
            #pragma fragment FragmentPass

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            TEXTURE2D(_DistortionNoise);    SAMPLER(sampler_DistortionNoise);
            TEXTURE2D(_WavedNoise);         SAMPLER(sampler_WavedNoise);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color01;
                half4 _Color02;
                half4 _Color03;
                half4 _Color04;
                float4 _DistortionNoise_ST;
                float4 _WavedNoise_ST;
                float4 _DistortionScale;

                half _EdgeWidth;
                half _EdgeSoftFactor;
                half _EdgeFactor;
                half _Mask01Exp;
                half4 _GradientThresholds;
                half4 _GradientSmoothness;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 texcoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord : TEXCOORD0;
                float4 positionOS : TEXCOORD1;
                
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // 在片段着色器中
            half3 MixMultipleColors(float t)
            {
                // 重新映射噪声值到0-3范围(对应4种颜色)
                float indexF = t * 4.0;
                int index = floor(indexF); // 0, 1, 或 2
                float frac = indexF - index; // 小数部分
                
                // 选择相邻两种颜色
                half3 colorA, colorB;
                if (index == 0)
                {
                    colorA = _Color01.rgb;
                    colorB = _Color02.rgb;
                }
                else if (index == 1)
                {
                    colorA = _Color02.rgb;
                    colorB = _Color03.rgb;
                }
                else
                {
                    colorA = _Color03.rgb;
                    colorB = _Color04.rgb;
                }
                
                // 混合这两种颜色
                return lerp(colorA, colorB, smoothstep(0.0, 1.0, frac));
            }

            half3 SampleGradient(float t, float smoothing)
            {
                float steps = 5 - 1;
                
                // 计算梯度索引和分数
                float index = t * steps;
                int i0 = floor(index);
                int i1 = min(i0 + 1, steps);
                float frac = index - i0;
                
                // 平滑过渡
                if (smoothing > 0)
                {
                    frac = smoothstep(0.0, 1.0, frac);
                }
                
                // 根据索引获取颜色
                half3 color0, color1;
                if (i0 == 0) color0 = _Color01.rgb;
                else if (i0 == 1) color0 = _Color02.rgb;
                else if (i0 == 2) color0 = _Color03.rgb;
                else color0 = _Color04.rgb;
                    
                if (i1 == 0) color1 = _Color01.rgb;
                else if (i1 == 1) color1 = _Color02.rgb;
                else if (i1 == 2) color1 = _Color03.rgb;
                else color1 = _Color04.rgb;
                    
                // 混合颜色
                return lerp(color0, color1, frac);
            }

            Varyings VertexPass(Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(vsIn);
                UNITY_TRANSFER_INSTANCE_ID(vsIn, vsOut);

                vsOut.positionCS = TransformObjectToHClip(vsIn.positionOS);
                vsOut.texcoord = vsIn.texcoord;
                vsOut.positionOS = vsIn.positionOS;
                return vsOut;
            }

            half4 FragmentPass(Varyings fsIn) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(fsIn);

                half softEdgeFactor = (_EdgeFactor + 0.001) * (_EdgeSoftFactor + 1.0);
                
                float2 distortionNoiseUV = fsIn.texcoord * _DistortionNoise_ST.xy + _DistortionNoise_ST.zw;
                half4 distortionNoise = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, distortionNoiseUV);
                float2 wavedNoiseUV = fsIn.texcoord + distortionNoise.rg * _DistortionScale.xy;
                wavedNoiseUV = wavedNoiseUV * _WavedNoise_ST.xy + _WavedNoise_ST.zw;
                wavedNoiseUV.y += _Time.y * 0.08;
                half4 wavedNoise = SAMPLE_TEXTURE2D(_WavedNoise, sampler_WavedNoise, wavedNoiseUV.xy);

                half noiseMask = saturate(pow(wavedNoise.r, _Mask01Exp));
                noiseMask = saturate((noiseMask / _EdgeWidth + noiseMask) * 0.5);
                half smoothedMask = smoothstep(softEdgeFactor - _EdgeSoftFactor, softEdgeFactor, noiseMask);

                float noise = smoothedMask;
                
                // 计算四种颜色的权重
                float w1 = smoothstep(0.0, _GradientThresholds.x + _GradientSmoothness, noise) - smoothstep(_GradientThresholds.x - _GradientSmoothness, _GradientThresholds.x, noise);
                
                float w2 = smoothstep(_GradientThresholds.x - _GradientSmoothness, _GradientThresholds.x + _GradientSmoothness, noise) -
                smoothstep(_GradientThresholds.y - _GradientSmoothness, _GradientThresholds.y + _GradientSmoothness, noise);
                
                float w3 = smoothstep(_GradientThresholds.y - _GradientSmoothness, _GradientThresholds.y + _GradientSmoothness, noise) -
                smoothstep(_GradientThresholds.z - _GradientSmoothness, _GradientThresholds.z + _GradientSmoothness, noise);
                
                float w4 = smoothstep(_GradientThresholds.z - _GradientSmoothness, _GradientThresholds.z + _GradientSmoothness, noise);
                
                // 混合所有颜色
                half3 color = _Color01.rgb * w1 +
                    _Color02.rgb * w2 +
                    _Color03.rgb * w3 +
                    _Color04.rgb * w4;
                // color = lerp(color, _Color03.rgb, smoothedMask);

                half3 finalColor = SampleGradient(wavedNoise.r, _EdgeSoftFactor);
                // finalColor = MixMultipleColors(frac(wavedNoise.r + _Time.y * 0.1));
                finalColor = color;
                half alpha = 1;

                return half4(finalColor, alpha);
            }

            ENDHLSL
        }
    }
}
