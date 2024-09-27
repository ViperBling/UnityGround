Shader "Terrian/S_TextureBlend_Normal"
{
    Properties 
    {
        _LightColor("Light Color", Color) = (1,1,1,1)
        _Gloss ("_Gloss" , Range(0,1)) = 0.8
    	_Splat0 ("Layer 1(RGBA)", 2D) = "white" {}
        _BumpSplat0 ("Layer 1 Normal(Bump)", 2D) = "Bump" {}
    	_Splat1 ("Layer 2(RGBA)", 2D) = "white" {}
        _BumpSplat1 ("Layer 2 Normal(Bump)", 2D) = "Bump" {}
    	_Splat2 ("Layer 3(RGBA)", 2D) = "white" {}
        _BumpSplat2 ("Layer 3 Normal(Bump)", 2D) = "Bump" {}
        _Splat3 ("Layer 4(RGBA)", 2D) = "white" {}
        _BumpSplat3 ("Layer 4 Normal(Bump)", 2D) = "Bump" {}
    	_Control ("Control (RGBA)", 2D) = "white" {}
        _Weight ("Blend Weight" , Range(0.001,1)) = 0.2      
    }
    SubShader
    {
        Tags
        {
            "SplatCount" = "4"
            "RenderType" = "Opaque"
        }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex VertexPass
            #pragma fragment FragmentPass
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
            
            struct Attributes
            {
                float4 positionOS  : POSITION;
                float4 tangentOS   : TANGENT;
                float3 normalOS    : NORMAL;
                float4 texCoord    : TEXCOORD0;
                half4  vertexColor : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 texCoord         : TEXCOORD0;
                half4  controlAndSplat0 : TEXCOORD1;
                half4  splat1AndSplat2  : TEXCOORD2;
                half2 splat3            : TEXCOORD3;

                float4 tSpace0          : TEXCOORD4;
                float4 tSpace1          : TEXCOORD5;
                float4 tSpace2          : TEXCOORD6;
            };

            sampler2D _Control;    float4 _Control_ST;
            sampler2D _Splat0;     float4 _Splat0_ST;
            sampler2D _Splat1;     float4 _Splat1_ST;
            sampler2D _Splat2;     float4 _Splat2_ST;
            sampler2D _Splat3;     float4 _Splat3_ST;
            sampler2D _BumpSplat0, _BumpSplat1, _BumpSplat2, _BumpSplat3;
            
            half _Weight;
            half4 _LightDir;
            half4 _LightColor;
            half _Gloss;

            inline half4 LightingBlendModel(half3 albedo, half3 normal, half alpha, half3 lightDir, half3 viewDir, half atten)  
            {
                half4 col;
                
                half diffuseF = max(0, dot(normal, lightDir));
                
                _Gloss = pow(4096, _Gloss);
                half specF;
                half3 H = normalize(lightDir + viewDir);
                half specBase = max(0, dot(normal, H));
                specF = pow(specBase, _Gloss);

                col.rgb = albedo * _LightColor * diffuseF *atten + _LightColor * specF;
                col.a = alpha;
                return col;
            }
            
            inline half4 Blend(half depth1 ,half depth2, half depth3, half depth4, half4 control) 
            {
                half4 blend ;
                
                blend.r =depth1 * control.r;
                blend.g =depth2 * control.g;
                blend.b =depth3 * control.b;
                blend.a =depth4 * control.a;
                
                half ma = max(blend.r, max(blend.g, max(blend.b, blend.a)));
                blend = max(blend - ma +_Weight , 0) * control;
                return blend/(blend.r + blend.g + blend.b + blend.a);
            }

            Varyings VertexPass (Attributes vsIn)
            {
                Varyings vsOut = (Varyings)0;
                vsOut.positionCS = UnityObjectToClipPos(vsIn.positionOS);

                vsOut.controlAndSplat0.xy = TRANSFORM_TEX(vsIn.texCoord, _Control);
                vsOut.controlAndSplat0.zw = TRANSFORM_TEX(vsIn.texCoord, _Splat0);
                vsOut.splat1AndSplat2.xy = TRANSFORM_TEX(vsIn.texCoord, _Splat1);
                vsOut.splat1AndSplat2.zw = TRANSFORM_TEX(vsIn.texCoord, _Splat2);
                vsOut.splat3.xy = TRANSFORM_TEX(vsIn.texCoord, _Splat3);

                float3 positionWS = mul(unity_ObjectToWorld, vsIn.positionOS).xyz;
                float3 normalWS = UnityObjectToWorldNormal(vsIn.normalOS);
                float3 tangentWS = UnityObjectToWorldDir(vsIn.tangentOS.xyz);
                half sign = vsIn.tangentOS.w * unity_WorldTransformParams.w;
                half3 binormalWS = cross(normalWS, tangentWS) * sign;

                vsOut.tSpace0 = float4(tangentWS.x, binormalWS.x, normalWS.x, positionWS.x);
                vsOut.tSpace1 = float4(tangentWS.y, binormalWS.y, normalWS.y, positionWS.y);
                vsOut.tSpace2 = float4(tangentWS.z, binormalWS.z, normalWS.z, positionWS.z);
                
                return vsOut;
            }

            half4 FragmentPass (Varyings fsIn) : SV_Target
            {
                half4 splatControl = tex2D(_Control, fsIn.controlAndSplat0.xy);
                half4 layer1 = tex2D(_Splat0, fsIn.controlAndSplat0.zw);
                half4 layer2 = tex2D(_Splat1, fsIn.splat1AndSplat2.xy);
                half4 layer3 = tex2D(_Splat2, fsIn.splat1AndSplat2.zw);
                half4 layer4 = tex2D(_Splat3, fsIn.splat3);

                half3 normal1 = UnpackNormal(tex2D(_BumpSplat0, fsIn.controlAndSplat0.zw));
                half3 normal2 = UnpackNormal(tex2D(_BumpSplat1, fsIn.splat1AndSplat2.xy));
                half3 normal3 = UnpackNormal(tex2D(_BumpSplat2, fsIn.splat1AndSplat2.zw));
                half3 normal4 = UnpackNormal(tex2D(_BumpSplat3, fsIn.splat3));

                half4 blend = Blend(layer1.a, layer2.a, layer3.a, layer4.a, splatControl);

                half3 albedo = layer1 * blend.r + layer2 * blend.g + layer3 * blend.b + layer4 * blend.a;
                half3 normal = normal1 * blend.r + normal2 * blend.g + normal3 * blend.b + normal4 * blend.a;

                half3 normalWS = normalize(float3(dot(fsIn.tSpace0.xyz, normal), dot(fsIn.tSpace1.xyz, normal), dot(fsIn.tSpace2.xyz, normal)));
                
                float3 positionWS = float3(fsIn.tSpace0.w, fsIn.tSpace1.w, fsIn.tSpace2.w);
                half3 lightDirWS = normalize(UnityWorldSpaceLightDir(positionWS));
                half3 viewDirWS = normalize(UnityWorldSpaceViewDir(positionWS));

                half3 finalColor = LightingBlendModel(albedo, normalWS, 0.0, lightDirWS, viewDirWS, 1.0).rgb;
                
                return half4(finalColor, 1.0);
            }
            ENDCG
        }
    }
}
