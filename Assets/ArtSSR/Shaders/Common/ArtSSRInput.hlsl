#pragma once

#define BINARY_STEP_COUNT 16

TEXTURE2D(_CameraDepthTexture);                 SamplerState point_clamp_sampler;
TEXTURE2D(_ReflectedColorMap);       

TEXTURE2D_X(_GBuffer0);         // Diffuse
TEXTURE2D_X(_GBuffer1);         // Metal
TEXTURE2D_X(_GBuffer2);         // Normal and Smoothness
SamplerState sampler_GBuffer;


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