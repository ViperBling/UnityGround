Shader "VFX/S_Wings_Test1"
{
    Properties
    {
        _MainTex ("Mask Texture", 2D) = "white" {}
        
        [Header(Color Settings)]
        [HDR]_Color01 ("Inner Core Color", Color) = (1.5, 3.0, 8.0, 1)
        [HDR]_Color02 ("Mid Energy Color", Color) = (0.7, 0.2, 2.0, 1)
        [HDR]_Color03 ("Outer Energy Color", Color) = (0.5, 0.0, 1.0, 1)
        [HDR]_Color04 ("Edge Lightning Color", Color) = (0.1, 0.6, 1.0, 1)
        [Space(5)]
        
        [Header(Noise Maps)]
        _DistortionNoise ("Distortion Noise", 2D) = "white" {}
        _FlowNoise ("Energy Flow Noise", 2D) = "white" {}
        _LightningMask ("Lightning Pattern", 2D) = "white" {}
        [Space(5)]
        
        [Header(Animation)]
        _DistortionScale ("Distortion Scale", Vector) = (0.1, 0.1, 0, 0)
        _FlowSpeed ("Flow Speed", Range(0.1, 5)) = 0.8
        _PulseRate ("Pulse Rate", Range(0.1, 10)) = 2.5
        _PulseIntensity ("Pulse Intensity", Range(0, 1)) = 0.3
        [Space(5)]
        
        [Header(Edge Effects)]
        _EdgeWidth ("Edge Width", Range(0, 2)) = 0.4
        _EdgeSoftFactor ("Edge Softness", Range(0, 2)) = 0.5
        _EdgeFactor ("Edge Glow", Range(0, 1)) = 0.7
        _Mask01Exp ("Mask Power", Range(0.2, 5)) = 1
        [Space(5)]
        
        [Header(Lightning Effects)]
        _LightningSpeed ("Lightning Speed", Range(0.1, 20)) = 5
        _LightningIntensity ("Lightning Intensity", Range(0, 2)) = 0.5
        _LightningScale ("Lightning Scale", Range(0.2, 10)) = 3
        _GradientScale ("Color Gradient Scale", Range(0.1, 5)) = 1.2
        [Space(5)]
        
        [Header(Emission)]
        _EmissionIntensity ("Emission Power", Range(1, 10)) = 2
    }
    
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "IgnoreProjector"="True" }
        
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex VertexPass
            #pragma fragment FragmentPass
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            TEXTURE2D(_DistortionNoise);    SAMPLER(sampler_DistortionNoise);
            TEXTURE2D(_FlowNoise);          SAMPLER(sampler_FlowNoise);
            TEXTURE2D(_LightningMask);      SAMPLER(sampler_LightningMask);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color01;
                half4 _Color02;
                half4 _Color03;
                half4 _Color04;
                float4 _DistortionNoise_ST;
                float4 _FlowNoise_ST;
                float4 _LightningMask_ST;
                float4 _DistortionScale;
                
                half _EdgeWidth;
                half _EdgeSoftFactor;
                half _EdgeFactor;
                half _Mask01Exp;
                half _GradientScale;
                half _FlowSpeed;
                half _PulseRate;
                half _PulseIntensity;
                half _LightningSpeed;
                half _LightningIntensity;
                half _LightningScale;
                half _EmissionIntensity;
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
            
            // 能量梯度颜色
            half3 EnergyGradient(float t)
            {
                // 应用渐变缩放参数
                t = pow(t, _GradientScale);
                
                // 在4个颜色间创建平滑渐变 - 带电流效果的梯度
                if (t < 0.33) {
                    return lerp(_Color01.rgb, _Color02.rgb, smoothstep(0.0, 0.33, t));
                } else if (t < 0.66) {
                    return lerp(_Color02.rgb, _Color03.rgb, smoothstep(0.33, 0.66, t));
                } else {
                    return lerp(_Color03.rgb, _Color04.rgb, smoothstep(0.66, 1.0, t));
                }
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
                float2 uv = fsIn.texcoord;
                
                // 基础遮罩
                half4 mainMask = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                
                // 电流脉冲效果
                float pulseEffect = sin(_Time.y * _PulseRate) * 0.5 + 0.5;
                pulseEffect = lerp(1.0, pulseEffect, _PulseIntensity);
                
                // 主扭曲效果
                float2 distortionUV1 = uv * _DistortionNoise_ST.xy + _DistortionNoise_ST.zw + float2(_Time.y * 0.17, _Time.y * -0.13);
                float2 distortionUV2 = uv * _DistortionNoise_ST.xy * 1.4 + _DistortionNoise_ST.zw + float2(-_Time.y * 0.22, _Time.y * 0.18);
                half4 distortion1 = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, distortionUV1);
                half4 distortion2 = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, distortionUV2);
                
                // 组合两个扭曲图层，增加复杂性
                half2 finalDistortion = (distortion1.rg * 2.0 - 1.0) + (distortion2.rg * 2.0 - 1.0);
                finalDistortion *= _DistortionScale.xy * pulseEffect;
                
                // 能量流动效果
                float2 flowUV = uv + finalDistortion * 0.5;
                flowUV = flowUV * _FlowNoise_ST.xy + _FlowNoise_ST.zw;
                
                // 创建旋转流动效果
                float flowTime = _Time.y * _FlowSpeed;
                float2 flowUV1 = flowUV + flowTime * float2(0.1, 0.2);
                float2 flowUV2 = flowUV + flowTime * float2(-0.15, -0.1) + 0.5; // 偏移第二层以增加复杂性
                
                half4 flowNoise1 = SAMPLE_TEXTURE2D(_FlowNoise, sampler_FlowNoise, flowUV1);
                half4 flowNoise2 = SAMPLE_TEXTURE2D(_FlowNoise, sampler_FlowNoise, flowUV2);
                
                // 组合两层能量流，增加深度
                half energyFlow = saturate(flowNoise1.r * flowNoise2.r + flowNoise1.g * 0.5);
                
                // 闪电效果
                float2 lightningUV = uv * _LightningScale + finalDistortion * 0.2;
                lightningUV.x += _Time.y * _LightningSpeed * 0.1;
                lightningUV.y -= _Time.y * _LightningSpeed * 0.17;
                half4 lightningPattern = SAMPLE_TEXTURE2D(_LightningMask, sampler_LightningMask, lightningUV);
                
                // 创建闪电强度变化
                float lightningFlicker = frac(sin(_Time.y * _LightningSpeed) * 12345.6789);
                float lightningIntensity = lightningPattern.r * lightningFlicker * _LightningIntensity;
                
                // 最终能量/扭曲掩码
                half noiseMask = saturate(pow(energyFlow, _Mask01Exp));
                noiseMask = saturate((noiseMask / _EdgeWidth + noiseMask) * 0.5);
                
                // 边缘软化处理
                half softEdgeFactor = (_EdgeFactor + 0.001) * (_EdgeSoftFactor + 1.0);
                half smoothedMask = smoothstep(softEdgeFactor - _EdgeSoftFactor, softEdgeFactor, noiseMask);
                
                // 将闪电添加到能量流中
                half energyWithLightning = saturate(smoothedMask + lightningIntensity);
                
                // 使用梯度颜色和能量强度
                float colorIndex = flowNoise1.g * 0.7 + flowNoise2.b * 0.3 + lightningIntensity * 0.4;
                half3 finalColor = EnergyGradient(colorIndex) * energyWithLightning;
                
                // 添加闪电高光
                finalColor += _Color04.rgb * lightningIntensity * 2.0;
                
                // 应用发光强度
                finalColor *= _EmissionIntensity;
                
                // 计算透明度 - 考虑主遮罩和能量强度
                half alpha = energyWithLightning * mainMask.r;
                
                return half4(finalColor, alpha);
            }
            
            ENDHLSL
        }
    }
}