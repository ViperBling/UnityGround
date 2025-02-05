#pragma once

TEXTURE2D(_CameraOpaqueTexture);                SAMPLER(sampler_CameraOpaqueTexture);
TEXTURE2D(_CameraDepthTexture);                 SAMPLER(sampler_CameraDepthTexture);
TEXTURE2D(_ReflectedColorMap);
TEXTURE2D(_TempPaddedSceneColor);    SAMPLER(sampler_TempPaddedSceneColor);
TEXTURE2D(_MainTex);                 SAMPLER(sampler_MainTex);

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness
SAMPLER(sampler_point_clamp);

CBUFFER_START(UnityPerMaterial)
float4x4 _ProjectionMatrixSSR;
float4x4 _InvProjectionMatrixSSR;
float4x4 _ViewMatrixSSR;
float4x4 _InvViewMatrixSSR;

float3 _WorldSpaceViewDir;
float _RenderScale;
float _StepStride;
float _NumSteps;
float _MinSmoothness;
int _ReflectSky;

float2 _CrossEpsilon;

float2 _ScreenResolution;
float2 _PaddedResolution;
float2 _PaddedScale;
float _ArtSSR_GlobalScale;
float _ArtSSR_GlobalInvScale;

int _Frame;
int _DitherMode;
CBUFFER_END