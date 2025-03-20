#pragma once

TEXTURE2D(_MainTex);             SAMPLER(sampler_MainTex);
TEXTURE2D(_ColorBlendingTex);    SAMPLER(sampler_ColorBlendingTex);
TEXTURE2D(_WindNoiseTexture);    SAMPLER(sampler_WindNoiseTexture);

CBUFFER_START(UnityPerMaterial)
    float4 _MainTex_ST;
    float4 _ColorBlendingTex_ST;
    half4 _GrassTopColor;
    half4 _GrassBottomColor;
    half4 _GrassBaseColor;

    half _RandomNormal;
    half _WrapValue;
    half _SpecularShininess;
    half _SpecularIntensity;

    half4 _WindNoiseParam;
    half4 _WindBending;

    StructuredBuffer<float3> _InstancePositionBuffer;
    StructuredBuffer<uint> _VisibleInstanceIndexBuffer;
CBUFFER_END

#define _WindTilling    _WindNoiseParam.xy
#define _WindIntensity  _WindNoiseParam.zw

#define _WindBendingLow _WindBending.x
#define _WindBendingHigh _WindBending.y

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 texCoord : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 texCoord : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 positionOS : TEXCOORD2;
    float3 perGrassPivotPosWS : TEXCOORD3;
    float3 normalWS : NORMAL;
};

half3 SimpleLit(half3 albedo, half3 normalWS, half3 viewDirWS, half3 lightDir, half3 lightColor, half attenuation, half occlusion)
{
    float NoV = saturate(dot(normalWS, viewDirWS));
    float NoL = saturate(dot(normalWS, lightDir));
    half3 H = normalize(lightDir + viewDirWS);
    float NoH = saturate(dot(normalWS, H));
    float VoH = saturate(dot(viewDirWS, H));
    half3 reflectDirWS = reflect(-viewDirWS, normalWS);

    half3 lighting = lightColor * attenuation;

    half tipMask = smoothstep(0.6, 1.0, occlusion);
    
    half backTranslucency = pow(saturate(dot(-lightDir, viewDirWS)), 1.5) * 1 * tipMask;

    half wrapValue = max(0, (NoL + _WrapValue) / (1 + _WrapValue));
    half3 directDiffuse = (wrapValue + backTranslucency) * albedo;
    directDiffuse *= tipMask;
    half directSpecular = pow(NoH, _SpecularShininess) * _SpecularIntensity;
    directSpecular *= tipMask;
    half3 directColor = lighting * (directDiffuse + directSpecular);

    half3 indirectDiffuse = SampleSH(normalWS);
    // indirectDiffuse = lerp(indirectDiffuse,
    //     floor(indirectDiffuse * 3) / 3,
    //     0.1);
    // indirectDiffuse = lerp(0, indirectDiffuse, occlusion);
    indirectDiffuse = indirectDiffuse * saturate(1 - attenuation) * tipMask + indirectDiffuse;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectDirWS, 0.05, occlusion);
    // indirectSpecular *= tipMask;
    half3 indirectColor = (indirectDiffuse + indirectSpecular) * albedo;

    half rim = pow(1.0 - NoV, 7) * 2 * tipMask;
    half3 rimLight = lighting * rim;

    half3 color = directColor + indirectColor + rimLight;
    // color = indirectDiffuse;
    return color;
}