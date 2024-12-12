#pragma once

void base_VertexWorldSpace(inout float4 positionOS, inout float3 positionWS);
void override_VertexWorldSpace(inout float4 positionOS, inout float3 positionWS, Attributes input, inout Varyings output);
void override_TransformTexcoord(Attributes input, inout Varyings output);
void override_VertexGI(Attributes input, inout Varyings output);
void override_AfterLighting(inout half4 color, inout PerFragmentData fragmentData);
void override_AfterVertex(Attributes input, inout Varyings output);

inline void base_VertexTBN(Attributes input, float3 positionWS, inout VertexPositionInputs vertexInput, inout VertexNormalInputs normalInput, inout Varyings output);
inline void override_VertexTBN(Attributes input, float3 positionWS, inout VertexPositionInputs vertexInput, inout VertexNormalInputs normalInput, inout Varyings output);
void base_VertexFog(float3 positionWS, VertexPositionInputs vertexInput, VertexNormalInputs normalInput, inout Varyings output);
inline void base_Vertex(Attributes input, inout Varyings output);
inline void base_VertexGI(Attributes input, inout Varyings output);
inline void base_TransformTexcoord(Attributes input, inout Varyings output);
inline void base_InitializeSurfaceData(Varyings input, inout SurfaceData output);
inline half3 base_GlobalIllumination(inout PerFragmentData fragmentData);
inline void base_InitializeInputData(Varyings input, half3 normalTS, out InputData inputData);
inline half3 base_SurfaceLighting(inout PerFragmentData fragmentData);
inline half4 base_Lighting(inout PerFragmentData fragmentData);
inline void base_AfterLighting(inout half4 color, inout PerFragmentData fragmentData);
inline void base_AfterVertex(Attributes input, inout Varyings output);
inline void PerfectInitializeGIData(Varyings input, float3 normalWS, inout InputData inputData);
inline void PerfectTransferViewDirection(Varyings input, inout InputData inputData);
inline void PerfectTransferTBN(Varyings input, half3 normalTS, inout InputData inputData);
inline void base_ApplyWeather(Varyings input, inout InputData inputData, inout SurfaceData surfaceData);
//#define _OVERRIDE_LIGHTING
half4 override_Lighting(PerFragmentData fragmentData);

inline half3 override_GlobalIllumination(inout PerFragmentData fragmentData);
inline half3 override_SurfaceLighting(inout PerFragmentData fragmentData);

// #if defined(UNITY_PASS_META)
//     #include "Packages/com.pwrd.render-pipelines.universal/Shaders/Pipeline/Modules/BaseMetaInput.hlsl"
//     inline void base_InitializeMetaInput(Varyings input, BRDFData brdfData, SurfaceData surfaceData, inout MetaInput metaInput);
//     
// #endif