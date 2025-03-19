#pragma once

TEXTURE2D(_MainTex);             SAMPLER(sampler_MainTex);
TEXTURE2D(_WindNoiseTexture);    SAMPLER(sampler_WindNoiseTexture);

CBUFFER_START(UnityPerMaterial)
    float4 _MainTex_ST;
    half4 _TopColor;
    half4 _BottomColor;

    half _RandomNormal;
    half _WrapValue;
    half _SpecularShininess;
    half _SpecularIntensity;

    half4 _WindNoiseParam;

    StructuredBuffer<float3> _InstancePositionBuffer;
    StructuredBuffer<uint> _VisibleInstanceIndexBuffer;
CBUFFER_END

#define _WindTilling    _WindNoiseParam.xy
#define _WindIntensity  _WindNoiseParam.zw

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
    float3 perGrassPivotPosWS : TEXCOORD2;
    float windFactor : TEXCOORD3;
    float3 normalWS : NORMAL;
    float3 color : COLOR;
};

half3 SimpleLit(half3 albedo, half3 normalWS, half3 viewDirWS, half3 lightDir, half3 lighting, half occlusion)
{
    float NoV = saturate(dot(normalWS, viewDirWS));
    float NoL = saturate(dot(normalWS, lightDir));
    half3 H = normalize(lightDir + viewDirWS);
    float NoH = saturate(dot(normalWS, H));
    float VoH = saturate(dot(viewDirWS, H));
    half3 reflectDirWS = reflect(-viewDirWS, normalWS);

    half colorRemap = smoothstep(0.6, 1.0, occlusion);
    
    half backTranslucency = pow(saturate(dot(-lightDir, viewDirWS)), 1.5) * 1 * colorRemap;

    half wrapValue = max(0, (NoL + _WrapValue) / (1 + _WrapValue));
    half3 directDiffuse = (wrapValue + backTranslucency) * albedo;
    half directSpecular = pow(NoH, _SpecularShininess) * _SpecularIntensity;
    directSpecular *= colorRemap;
    half3 directColor = lighting * (directDiffuse + directSpecular);

    half3 indirectDiffuse = SampleSH(normalWS);
    // indirectDiffuse = lerp(indirectDiffuse,
    //     floor(indirectDiffuse * 3) / 3,
    //     0.1);
    // indirectDiffuse = lerp(0, indirectDiffuse, occlusion);
    indirectDiffuse *= colorRemap;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectDirWS, 0.05, occlusion);
    indirectSpecular *= colorRemap;
    half3 indirectColor = (indirectDiffuse + indirectSpecular) * albedo;
    // indirectColor = lerp(0, indirectColor, occlusion);

    half3 color = directColor + indirectColor;
    // color = directDiffuse;
    return color;
}