#pragma once

#define BINARY_STEP_COUNT 16

TEXTURE2D(_CameraDepthTexture);                 SamplerState point_clamp_sampler;
TEXTURE2D(_ReflectedColorMap);
TEXTURE2D(_TempPaddedSceneColor);    SAMPLER(sampler_TempPaddedSceneColor);
TEXTURE2D(_MainTex);                 SAMPLER(sampler_MainTex);

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness
SAMPLER(sampler_point_clamp);

float4 _CameraViewTopLeftCorner;
float4 _CameraXExtent;
float4 _CameraYExtent;
float4 _ProjectionParamsSSR;

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