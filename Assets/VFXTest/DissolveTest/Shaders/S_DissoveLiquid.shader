Shader "Effect/DissolveLiquid" 
{
    Properties 
	{
		[HDR] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
	    [HDR] _DissolveColor ("_Dissolve Color", Color) = (1, 1, 1, 1)
	    _MainTex ("Base Texture", 2D) = "white" {}
	    _NormalTex ("Base Normal", 2D) = "bump" {}
	    _DissolveTex ("Dissolve Texture", 2D) = "white" {}
	    _MainAlpha ("Main Alpha", Range(0, 10)) = 5
	    _DissolveTexWide ("Dissolve Texture Wide", Range(1, 10)) = 1
        _DissolveFactor ("Dissolve Factor", Range(0, 1)) = 0
        _DissolveEdgeSoft ("Dissolve Edge", Range(0, 1)) = 0
	    _DissolveExp ("Dissolve Exp", Range(0, 1)) = 0
        _NormalOffset ("Dynamic Normal Offset", Range(0, 1)) = 0
	    _EdgeStrength ("Dynamic Normal Strength", Range(1, 100)) = 1
	    _LightScale ("Light Scale", Range(0, 1)) = 1
	}
    SubShader 
	{
        Tags{ "RenderType" = "Transparent" "Queue" = "Transparent" }
		
        Pass 
		{
			Name "FORWARD"
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off
			
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/lighting.hlsl"

            half4 _BaseColor;
            half4 _DissolveColor;
            sampler2D _CameraOpaqueTexture;
            sampler2D _MainTex;     float4 _MainTex_ST;
            sampler2D _NormalTex;   float4 _NormalTex_ST;
            sampler2D _DissolveTex; float4 _DissolveTex_ST;

            half _MainAlpha;
            half _DissolveTexWide;
            half _DissolveFactor;
            half _DissolveEdgeSoft;
            half _DissolveExp;
            half _NormalOffset;
            half _EdgeStrength;
            half _LightScale;

            struct VertexInput
            {
            	float4 positionOS	: POSITION;
            	float4 texcoord		: TEXCOORD0;
            	float3 normalOS		: NORMAL;
            	float4 tangentOS	: TANGENT;
            	float4 color		: COLOR;
            	UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct VertexOutput
            {
            	float4 positionCS   : SV_POSITION;
            	float2 uv		    : TEXCOORD0;
            	float4 tSpace0		: TEXCOORD1;
            	float4 tSpace1		: TEXCOORD2;
            	float4 tSpace2		: TEXCOORD3;
            	float4 screenPos    : TEXCOORD4;
            	half4 vertexColor  : COLOR0;
            	UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            float3 WorldNormal(VertexOutput input, float3 normal)
            {
            	return normalize(float3(dot(input.tSpace0.xyz, normal), dot(input.tSpace1.xyz, normal), dot(input.tSpace2.xyz, normal)));
            }

            half4 SimpleBlinnPhong(half3 normal, half3 lightDir, half3 viewDir, half shininess)
            {
                // lightDir.y *= -1;
            	half3 halfDir = normalize(lightDir + viewDir);
            	half spec = pow(saturate(dot(normal, halfDir)), shininess);
            	half diff = saturate(dot(normal, lightDir));
            	half4 color = (diff + spec) * _LightScale;
            	return color;
            }

            float4 WaterDissolveEffect(VertexOutput input, float3 lightDir, float3 viewDir)
            {
            	float2 baseUV = TRANSFORM_TEX(input.uv, _MainTex);
            	float2 normalUV = TRANSFORM_TEX(input.uv, _NormalTex);
            	
            	float4 dissolveBaseColor = tex2D(_MainTex, baseUV);
            	float3 dissolveTexNormal = UnpackNormalScale(tex2D(_NormalTex, normalUV), 2);
            	
            	// #ifdef USE_VERTEX_COLOR
            	// float dissolveFactor = 1 - input.vertexColor.a;
            	// float mainAlpha = dissolveBaseColor.a * _BloodColor.a;
            	// #else
            	float dissolveFactor = _DissolveFactor;
            	float mainAlpha = input.vertexColor.a * dissolveBaseColor.a * _BaseColor.a;
            	// #endif
            	mainAlpha *= _MainAlpha;
            	
            	float softedFactor = (dissolveFactor + 0.001) * (_DissolveEdgeSoft + 1.0);
            	
            	float uvOffset = pow(_NormalOffset, 3.0) * 0.1;
            	float2 uv  = input.uv;
            	float2 uv0 = input.uv;
            	float2 uv1 = input.uv;
            
            	uv  = TRANSFORM_TEX(uv,  _DissolveTex);
            	uv0 = TRANSFORM_TEX(uv0, _DissolveTex);
            	uv1 = TRANSFORM_TEX(uv1, _DissolveTex);
            	uv0 = float2(uv0.x + uvOffset, uv0.y);
            	uv1 = float2(uv1.x, uv1.y + uvOffset);
            	
            	float4 originNoise = tex2D(_DissolveTex, uv);
            	float4 noiseDx 	   = tex2D(_DissolveTex, uv0);
            	float4 noiseDy 	   = tex2D(_DissolveTex, uv1);
                // float4 originNoise = _DissolveTex.SampleLevel(sampler_Point_Repeat, uv, 0);
                // float4 noiseDx 	   = _DissolveTex.SampleLevel(sampler_Point_Repeat, uv0, 0);
            	// float4 noiseDy 	   = _DissolveTex.SampleLevel(sampler_Point_Repeat, uv1, 0);
            
            	float dissolveAlpha   = saturate(pow(originNoise.g , _DissolveExp));
            	float dissolveAlphaDx = saturate(pow(noiseDx.g, _DissolveExp));
            	float dissolveAlphaDy = saturate(pow(noiseDy.g, _DissolveExp));

                dissolveAlpha   = saturate((dissolveAlpha / _DissolveTexWide + dissolveAlpha) / 2.0);
                dissolveAlphaDx = saturate((dissolveAlphaDx / _DissolveTexWide + dissolveAlphaDx) / 2.0);
                dissolveAlphaDy = saturate((dissolveAlphaDy / _DissolveTexWide + dissolveAlphaDy) / 2.0);
            
            	float smoothedAlpha   = smoothstep(softedFactor - _DissolveEdgeSoft, softedFactor, dissolveAlpha);
            	float smoothedAlphaDx = smoothstep(softedFactor - _DissolveEdgeSoft, softedFactor, dissolveAlphaDx);
            	float smoothedAlphaDy = smoothstep(softedFactor - _DissolveEdgeSoft, softedFactor, dissolveAlphaDy);
            
            	float stepedAlpha = step(dissolveFactor + 0.001, smoothedAlpha);
            	float stepedAlphaDx = step(dissolveFactor + 0.001, smoothedAlphaDx);
            	float stepedAlphaDy = step(dissolveFactor + 0.001, smoothedAlphaDy);
            
            	// float disAlpha = step(dissolveFactor + 0.001, dissolveAlpha);
            	// float disAlphaDx = step(dissolveFactor + 0.001, dissolveAlphaDx);
            	// float disAlphaDy = step(dissolveFactor + 0.001, dissolveAlphaDy);
            
            	float3 ddx = float3(1.0, 0.0, (smoothedAlphaDx - smoothedAlpha) * _EdgeStrength * 10);
            	float3 ddy = float3(0.0, 1.0, (smoothedAlphaDy - smoothedAlpha) * _EdgeStrength * 10);
            
            	float3 dissolveNormal = normalize(cross(ddx, ddy));
                float3 blendedNormal = BlendNormal(dissolveTexNormal, dissolveNormal);
            	float3 normalWS = WorldNormal(input, blendedNormal);
            	
            	float outAlpha = saturate(smoothedAlpha * mainAlpha);
            	
            	float edgeAlpha = smoothedAlpha - stepedAlpha;
            	half4 baseColor = lerp(_BaseColor * dissolveBaseColor * smoothedAlpha, _DissolveColor, _DissolveColor.a);
            	half4 mainColor = lerp(_BaseColor * dissolveBaseColor, baseColor * edgeAlpha, edgeAlpha);
            	
            	half4 lighting = SimpleBlinnPhong(normalWS, lightDir, viewDir, 12.8);

                half3 halfDir = normalize(lightDir + viewDir);
            	half spec = pow(saturate(dot(normalWS, halfDir)), 12.8);
            	half diff = saturate(dot(normalWS, lightDir));
            	half4 color = (diff + spec) * _LightScale;
                
            	half4 finalColor = outAlpha * (mainColor + lighting);
            	
            	return float4(finalColor.rgb, outAlpha);
            }
            
            VertexOutput vert(VertexInput input)
            {
            	UNITY_SETUP_INSTANCE_ID(input);
            	
            	VertexOutput output = (VertexOutput)0;
            	UNITY_TRANSFER_INSTANCE_ID(input, output);
            	output.positionCS = TransformObjectToHClip(input.positionOS);
            	output.uv = input.texcoord.xy;

            	float3 worldPos = mul(unity_ObjectToWorld, input.positionOS).xyz;
            	float3 worldNormal = TransformObjectToWorldNormal(input.normalOS);
            	float3 worldTangent = TransformObjectToWorldDir(input.tangentOS.xyz);
            	half tangentSign = input.tangentOS.w * unity_WorldTransformParams.w;
				float3 worldBinormal = cross(worldNormal, worldTangent) * tangentSign;
				output.tSpace0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
            	output.tSpace1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
            	output.tSpace2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);

            	output.vertexColor = input.color;

                output.screenPos = ComputeScreenPos(output.positionCS);
            	
    			return output;
            }
            
            float4 frag(VertexOutput input) : SV_TARGET
            {
            	UNITY_SETUP_INSTANCE_ID(input);
            	
            	float3 worldPos = float3(input.tSpace0.w, input.tSpace1.w, input.tSpace2.w);
            	
            	float3 lightDir = normalize(GetMainLight().direction);
    			float3 viewDir = normalize(worldPos - _WorldSpaceCameraPos);

                float4 finalColor = WaterDissolveEffect(input, lightDir, viewDir);
                
                return finalColor;
            }
            ENDHLSL
        }
    }
}
