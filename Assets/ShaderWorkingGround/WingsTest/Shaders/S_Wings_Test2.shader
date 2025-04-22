Shader "VFX/S_Wings_Test2"
{
    Properties
    {
        _MainTex ("Wing Shape Mask", 2D) = "white" {}
        _FeatherTex ("Feather Texture", 2D) = "white" {}  // 新增：羽毛/纤维纹理
        
        [Header(Color Settings)]
        [HDR]_Color01 ("Inner Core Color (Blue)", Color) = (0.2, 1.0, 5.0, 1)
        [HDR]_Color02 ("Mid Energy Color (Purple)", Color) = (2.0, 0.2, 4.0, 1)
        [HDR]_Color03 ("Outer Energy Color (Pink)", Color) = (3.0, 0.0, 1.5, 1)
        [HDR]_Color04 ("Edge Lightning Color", Color) = (0.5, 2.0, 4.0, 1)
        [Space(5)]
        
        [Header(Noise Maps)]
        _DistortionNoise ("Distortion Noise", 2D) = "white" {}
        _FlowNoise ("Energy Flow Noise", 2D) = "white" {}
        _LightningMask ("Lightning Pattern", 2D) = "white" {}
        [Space(5)]
        
        [Header(Animation)]
        _DistortionScale ("Distortion Scale", Vector) = (0.15, 0.25, 0, 0)
        _FlowSpeed ("Flow Speed", Range(0.1, 5)) = 1.2
        _PulseRate ("Pulse Rate", Range(0.1, 10)) = 1.8
        _PulseIntensity ("Pulse Intensity", Range(0, 1)) = 0.3
        _VerticalFlowSpeed ("Vertical Flow Speed", Range(0, 2)) = 0.4  // 新增：垂直流动速度
        [Space(5)]
        
        [Header(Wing Shape)]
        _FeatherAmount ("Feather Amount", Range(0, 5)) = 2.0  // 新增：羽毛数量
        _FeatherLength ("Feather Length", Range(0, 2)) = 1.0  // 新增：羽毛长度
        _WingAspect ("Wing Aspect Ratio", Range(0.5, 5)) = 2.2  // 新增：翅膀长宽比
        [Space(5)]
        
        [Header(Edge Effects)]
        _EdgeWidth ("Edge Width", Range(0, 2)) = 0.4
        _EdgeSoftFactor ("Edge Softness", Range(0, 2)) = 0.5
        _EdgeFactor ("Edge Glow", Range(0, 1)) = 0.7
        _Mask01Exp ("Mask Power", Range(0.2, 5)) = 1.5
        [Space(5)]
        
        [Header(Lightning Effects)]
        _LightningSpeed ("Lightning Speed", Range(0.1, 20)) = 6.5
        _LightningIntensity ("Lightning Intensity", Range(0, 3)) = 1.2
        _LightningScale ("Lightning Scale", Range(0.2, 10)) = 3
        _GradientScale ("Color Gradient Scale", Range(0.1, 5)) = 1.2
        [Space(5)]
        
        [Header(Emission)]
        _EmissionIntensity ("Emission Power", Range(1, 10)) = 2.5
    }
    
    // SubShader 部分沿用您现有的代码结构
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
            
            // 纹理声明 - 添加了羽毛纹理
            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            TEXTURE2D(_DistortionNoise);    SAMPLER(sampler_DistortionNoise);
            TEXTURE2D(_FlowNoise);          SAMPLER(sampler_FlowNoise);
            TEXTURE2D(_LightningMask);      SAMPLER(sampler_LightningMask);
            TEXTURE2D(_FeatherTex);         SAMPLER(sampler_FeatherTex);
            
            // 在CBUFFER中添加新的参数
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color01;
                half4 _Color02;
                half4 _Color03;
                half4 _Color04;
                float4 _DistortionNoise_ST;
                float4 _FlowNoise_ST;
                float4 _LightningMask_ST;
                float4 _FeatherTex_ST;
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
                half _VerticalFlowSpeed;
                half _FeatherAmount;
                half _FeatherLength;
                half _WingAspect;
            CBUFFER_END
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 texcoord : TEXCOORD0;
                float4 color : COLOR;  // 添加顶点颜色输入
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord : TEXCOORD0;
                float4 positionOS : TEXCOORD1;
                float4 color : COLOR;  // 添加顶点颜色
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            // 能量梯度颜色 - 优化版本
            half3 EnergyGradient(float t)
            {
                // 应用渐变缩放参数，针对翅膀效果稍微调整了分布
                t = pow(t, _GradientScale);
                
                // 在4个颜色间创建平滑渐变
                if (t < 0.4) {
                    return lerp(_Color01.rgb, _Color02.rgb, smoothstep(0.0, 0.4, t));
                } else if (t < 0.7) {
                    return lerp(_Color02.rgb, _Color03.rgb, smoothstep(0.4, 0.7, t));
                } else {
                    return lerp(_Color03.rgb, _Color04.rgb, smoothstep(0.7, 1.0, t));
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
                vsOut.color = vsIn.color;
                return vsOut;
            }
            
            half4 FragmentPass(Varyings fsIn) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(fsIn);
                
                // 调整UV来匹配翅膀形状，应用翅膀长宽比
                float2 uv = fsIn.texcoord;
                uv.x = (uv.x - 0.5) * _WingAspect + 0.5;
                
                float timeFactor = _Time.y;
                
                // 基础翅膀形状遮罩
                half4 mainMask = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                
                // 电流脉冲效果 - 使用更加有机的波动
                float pulseBase = sin(timeFactor * _PulseRate) * 0.5 + 0.5;
                float pulseVariation = sin(timeFactor * _PulseRate * 1.3 + 1.57) * 0.5 + 0.5;  // 相位差异
                float pulseEffect = lerp(pulseBase, pulseVariation, uv.y) * _PulseIntensity + (1.0 - _PulseIntensity);
                
                // 主扭曲效果 - 与原始代码相似，稍作调整
                float2 distortionUV1 = uv * _DistortionNoise_ST.xy + _DistortionNoise_ST.zw + float2(timeFactor * 0.17, timeFactor * 0.13);
                float2 distortionUV2 = uv * _DistortionNoise_ST.xy * 1.4 + _DistortionNoise_ST.zw + float2(timeFactor * 0.22, timeFactor * 0.18);
                half4 distortion1 = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, distortionUV1);
                half4 distortion2 = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, distortionUV2);
                
                // 组合两个扭曲图层，增加复杂性
                half2 finalDistortion = (distortion1.rg * 2.0 - 1.0) + (distortion2.rg * 2.0 - 1.0);
                finalDistortion *= _DistortionScale.xy * pulseEffect;
                
                // 添加垂直流动组件，创造能量下流效果
                float2 verticalFlow = float2(0, -timeFactor * _VerticalFlowSpeed);
                
                // 能量流动效果
                float2 flowUV = uv + finalDistortion * 0.5;
                flowUV = flowUV * _FlowNoise_ST.xy + _FlowNoise_ST.zw;
                
                // 创建旋转流动效果，调整为更适合翅膀的模式
                float flowTime = timeFactor * _FlowSpeed;
                float2 flowUV1 = flowUV + flowTime * float2(0.1, 0.2) + verticalFlow;
                float2 flowUV2 = flowUV + flowTime * float2(-0.15, -0.1) + 0.5 + verticalFlow * 0.7;
                
                half4 flowNoise1 = SAMPLE_TEXTURE2D(_FlowNoise, sampler_FlowNoise, flowUV1);
                half4 flowNoise2 = SAMPLE_TEXTURE2D(_FlowNoise, sampler_FlowNoise, flowUV2);
                
                // 羽毛/纤维纹理效果
                float2 featherUV = uv * _FeatherTex_ST.xy + _FeatherTex_ST.zw;
                featherUV.y += timeFactor * _VerticalFlowSpeed * 0.2;  // 羽毛轻微飘动
                featherUV += finalDistortion * 0.15;  // 添加扭曲
                half4 featherTex = SAMPLE_TEXTURE2D(_FeatherTex, sampler_FeatherTex, featherUV);
                
                // 组合流动和羽毛纹理
                half energyFlow = saturate(flowNoise1.r * flowNoise2.r + flowNoise1.g * 0.5);
                half featherMask = featherTex.r * _FeatherAmount * (1.0 - pow(uv.y, _FeatherLength));
                energyFlow = lerp(energyFlow, featherMask, 0.4);  // 混合羽毛效果
                
                // 闪电效果
                float2 lightningUV = uv * _LightningScale + finalDistortion * 0.2;
                lightningUV.x += timeFactor * _LightningSpeed * 0.1;
                lightningUV.y -= timeFactor * _LightningSpeed * 0.17;
                half4 lightningPattern = SAMPLE_TEXTURE2D(_LightningMask, sampler_LightningMask, lightningUV);
                
                // 创建闪电强度变化 - 更明显的闪烁
                float lightningFlicker1 = frac(sin(timeFactor * _LightningSpeed) * 12345.6789);
                float lightningFlicker2 = frac(sin(timeFactor * _LightningSpeed * 1.4) * 23456.7891);
                float lightningIntensity = lightningPattern.r * (lightningFlicker1 * 0.7 + lightningFlicker2 * 0.3) * _LightningIntensity;
                
                // 最终能量/扭曲掩码
                half noiseMask = saturate(pow(energyFlow, _Mask01Exp));
                noiseMask = saturate((noiseMask / _EdgeWidth + noiseMask) * 0.5);
                
                // 边缘软化处理
                half softEdgeFactor = (_EdgeFactor + 0.001) * (_EdgeSoftFactor + 1.0);
                half smoothedMask = smoothstep(softEdgeFactor - _EdgeSoftFactor, softEdgeFactor, noiseMask);
                
                // 将闪电添加到能量流中
                half energyWithLightning = saturate(smoothedMask + lightningIntensity);
                
                // 使用梯度颜色和能量强度 - 调整为更加动态的颜色混合
                float colorNoise = flowNoise1.g * 0.4 + flowNoise2.b * 0.3 + lightningIntensity * 0.3;
                float colorIndex = uv.x * 0.4 + uv.y * 0.4 + colorNoise * 0.2; // 混合位置和噪声
                half3 finalColor = EnergyGradient(colorIndex) * energyWithLightning;
                
                // 添加闪电高光
                finalColor += _Color04.rgb * lightningIntensity * 2.5;
                
                // 添加羽毛高光
                finalColor += _Color02.rgb * featherMask * 0.5;
                
                // 应用发光强度和顶点颜色
                finalColor *= _EmissionIntensity * fsIn.color.rgb;
                
                // 计算透明度 - 考虑主遮罩和能量强度
                half alpha = energyWithLightning * mainMask.r * fsIn.color.a;
                
                return half4(finalColor, alpha);
            }
            
            ENDHLSL
        }
    }
}