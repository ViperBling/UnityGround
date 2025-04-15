using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Rendering.Universal;

namespace ArtSSR
{
    public partial class ArtSSRRenderFeature
    {
        internal class ArtSSRRenderPass : ScriptableRenderPass
        {
            const string m_ProfilingTag = "ArtSSR_RenderReflection";

            public ArtScreenSpaceReflection m_SSRVolume;
            
            // private static int m_Frame = 0; // Frame counter

            private readonly Material m_Material;
            private RTHandle m_SceneColorHandle;
            private RTHandle m_ReflectColorHandle;
            private RTHandle m_TemporalCurrentHandle;
            private RTHandle m_TemporalHistoryHandle;
            private RTHandle m_TempHandle;

            private const int m_LinearSSTracingPass = 0;
            private const int m_HiZTracingPass = 1;
            private const int m_SpatioFilterPass = 2;
            private const int m_TemporalFilterPass = 3;
            private const int m_CompositePass = 4;

            // private bool m_IsPadded = false;
            // private float m_Scale;
            private Vector2 m_ScreenResolution;
            private Matrix4x4 m_SSR_ProjectionMatrix = Matrix4x4.identity;
            private Matrix4x4 m_SSR_ViewProjectionMatrix = Matrix4x4.identity;
            private Matrix4x4 m_SSR_PrevViewProjectionMatrix = Matrix4x4.identity;
            private Matrix4x4 m_SSR_WorldToCameraMatrix = Matrix4x4.identity;
            private Matrix4x4 m_SSR_CameraToWorldMatrix = Matrix4x4.identity;
        
            private int m_SampleIndex = 0;
            private const int k_SampleCount = 64;
            private Vector2 m_RandomSample;

            private static readonly int m_SSR_JitterID = Shader.PropertyToID("_SSR_Jitter");
            private static readonly int m_SSR_BRDFBiasID = Shader.PropertyToID("_SSR_BRDFBias");
            private static readonly int m_SSR_NumStepsID = Shader.PropertyToID("_SSR_NumSteps");
            private static readonly int m_SSR_ScreenFadeID = Shader.PropertyToID("_SSR_ScreenFade");
            private static readonly int m_SSR_ThicknessID = Shader.PropertyToID("_SSR_Thickness");
            private static readonly int m_SSR_TemporalScaleID = Shader.PropertyToID("_SSR_TemporalScale");
            private static readonly int m_SSR_TemporalWeightID = Shader.PropertyToID("_SSR_TemporalWeight");
            private static readonly int m_SSR_ScreenResolutionID = Shader.PropertyToID("_SSR_ScreenResolution");
            private static readonly int m_SSR_RayStepStrideID = Shader.PropertyToID("_SSR_RayStepStride");
            private static readonly int m_SSR_ProjectionInfoID = Shader.PropertyToID("_SSR_ProjectionInfo");
            private static readonly int m_SSR_TraceDistanceID = Shader.PropertyToID("_SSR_TraceDistance");
            private static readonly int m_SSR_BlueNoiseTextureID = Shader.PropertyToID("_SSR_BlueNoiseTexture");
            private static readonly int m_SSR_BRDFLUTID = Shader.PropertyToID("_SSR_BRDFLUT");
            private static readonly int m_SSR_ProjectionMatrixID = Shader.PropertyToID("_SSR_ProjectionMatrix");
            private static readonly int m_SSR_ViewProjectionMatrixID = Shader.PropertyToID("_SSR_ViewProjectionMatrix");
            private static readonly int m_SSR_PrevViewProjectionMatrixID = Shader.PropertyToID("_SSR_PrevViewProjectionMatrix");
            private static readonly int m_SSR_InvProjectionMatrixID = Shader.PropertyToID("_SSR_InvProjectionMatrix");
            private static readonly int m_SSR_InvViewProjectionMatrixID = Shader.PropertyToID("_SSR_InvViewProjectionMatrix");
            private static readonly int m_SSR_WorldToCameraMatrixID = Shader.PropertyToID("_SSR_WorldToCameraMatrix");
            private static readonly int m_SSR_CameraToWorldMatrixID = Shader.PropertyToID("_SSR_CameraToWorldMatrix");
            private static readonly int m_SSR_ProjectToPixelMatrixID = Shader.PropertyToID("_SSR_ProjectToPixelMatrix");

            public ArtSSRRenderPass(Material material)
            {
                m_Material = material;
            }

            public void Dispose()
            {
                m_SceneColorHandle?.Release();
                m_ReflectColorHandle?.Release();
                m_TemporalCurrentHandle?.Release();
                m_TemporalHistoryHandle?.Release();
                m_TempHandle?.Release();
            }

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraRTDesc)
            {
                base.Configure(cmd, cameraRTDesc);
                m_RandomSample = GenerateRandomOffset();
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.useMipMap = true;
                desc.colorFormat = RenderTextureFormat.ARGBFloat;

                FilterMode filterMode = FilterMode.Bilinear;
                RenderingUtils.ReAllocateIfNeeded(ref m_SceneColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSR_SceneColorTexture");
                filterMode = FilterMode.Point;
                desc.useMipMap = false;
                RenderingUtils.ReAllocateIfNeeded(ref m_ReflectColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSR_ReflectionColorTexture");
                RenderingUtils.ReAllocateIfNeeded(ref m_TemporalCurrentHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSR_TemporalCurrentTexture");
                RenderingUtils.ReAllocateIfNeeded(ref m_TemporalHistoryHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSR_TemporalHistoryTexture");
                RenderingUtils.ReAllocateIfNeeded(ref m_TempHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSR_TempTexture");

                SetMaterialProperties(renderingData);
                
                ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Motion);
                ConfigureTarget(m_SceneColorHandle, m_SceneColorHandle);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                m_SceneColorHandle = null;
                m_ReflectColorHandle = null;
                m_TemporalCurrentHandle = null;
                m_TemporalHistoryHandle = null;
                m_TempHandle = null;
            }

            public override void FrameCleanup(CommandBuffer cmd)
            {
                if (m_SceneColorHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_SceneColorHandle.name));
                if (m_ReflectColorHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_ReflectColorHandle.name));
                if (m_TemporalCurrentHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_TemporalCurrentHandle.name));
                if (m_TemporalHistoryHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_TemporalHistoryHandle.name));
                if (m_TempHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_TempHandle.name));
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                // if (m_Material == null) return;

                CommandBuffer cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag)))
                {
                //     m_Material.SetVector(m_WorldSpaceViewDirID, renderingData.cameraData.camera.transform.forward);

                //     var renderCameraData = renderingData.cameraData;
                //     Matrix4x4 currVPMat = renderCameraData.GetGPUProjectionMatrix() * renderCameraData.GetViewMatrix();
                //     cmd.SetGlobalMatrix(m_PrevViewProjMatrixID, m_PrevViewProjMatrix);

                    // 1. 获取SceneColor
                    Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, m_SceneColorHandle);

                    // 2. 利用SceneColor进行反射计算，得到HitUV、Mask
                    if (m_SSRVolume.m_MarchingMode == ArtScreenSpaceReflection.RayMarchingMode.LinearScreenSpaceTracing)
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: m_LinearSSTracingPass);
                    }
                    else
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: m_HiZTracingPass);
                    }

                    // 3. 利用Hit数据进行空间滤波
                    cmd.SetGlobalTexture(m_SceneColorHandle.name, m_SceneColorHandle);
                    Blitter.BlitCameraTexture(cmd, m_ReflectColorHandle, m_TemporalCurrentHandle, m_Material, pass: m_SpatioFilterPass);

                    bool useTemporalFiltering = m_SSRVolume.m_UseTemporalFilter.value;
                    // 4. Temporal Filter
                    if (useTemporalFiltering)
                    {
                        cmd.SetGlobalTexture(m_ReflectColorHandle.name, m_ReflectColorHandle);
                        cmd.SetGlobalTexture(m_TemporalHistoryHandle.name, m_TemporalHistoryHandle);
                        Blitter.BlitCameraTexture(cmd, m_TemporalCurrentHandle, m_TempHandle, m_Material, pass: m_TemporalFilterPass);
                        cmd.CopyTexture(m_TempHandle, m_TemporalHistoryHandle);

                        Blitter.BlitCameraTexture(cmd, m_TempHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass: m_CompositePass);
                    }
                    else
                    {
                        Blitter.BlitCameraTexture(cmd, m_TemporalCurrentHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass: m_CompositePass);
                    }


                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    CommandBufferPool.Release(cmd);
                    m_SSR_PrevViewProjectionMatrix = m_SSR_ViewProjectionMatrix;
                }
            }

            private void SetMaterialProperties(RenderingData renderingData)
            {
                var camera = renderingData.cameraData.camera;
                Vector2 halfCameraSize = new Vector2(camera.pixelWidth, camera.pixelHeight) * 0.5f;

                m_ScreenResolution.x = camera.pixelWidth;
                m_ScreenResolution.y = camera.pixelHeight;

                m_Material.SetTexture(m_SSR_BlueNoiseTextureID, m_SSRVolume.m_BlueNoiseTexture.value);
                m_Material.SetTexture(m_SSR_BRDFLUTID, m_SSRVolume.m_BRDFLUT.value);

                m_Material.SetFloat(m_SSR_TraceDistanceID, m_SSRVolume.m_LinearRayDistance.value);
                m_Material.SetFloat(m_SSR_TemporalScaleID, m_SSRVolume.m_TemporalScale.value);
                m_Material.SetFloat(m_SSR_TemporalWeightID, m_SSRVolume.m_TemporalWeight.value);
                m_Material.SetVector(m_SSR_ScreenResolutionID, new Vector4(m_ScreenResolution.x, m_ScreenResolution.y, 1.0f / m_ScreenResolution.x, 1.0f / m_ScreenResolution.y));
                m_Material.SetFloat(m_SSR_ScreenFadeID, m_SSRVolume.m_EdgeFade.value);
                m_Material.SetFloat(m_SSR_ThicknessID, m_SSRVolume.m_ThicknessScale.value);
                m_Material.SetFloat(m_SSR_RayStepStrideID, m_SSRVolume.m_LinearRayStepSize.value);
                m_Material.SetFloat(m_SSR_NumStepsID, m_SSRVolume.m_LinearRaySteps.value);
                m_Material.SetFloat(m_SSR_BRDFBiasID, m_SSRVolume.m_BRDFBias.value);
                m_Material.SetVector(m_SSR_JitterID, new Vector4(m_ScreenResolution.x / 1024.0f, m_ScreenResolution.y / 1024.0f, m_RandomSample.x, m_RandomSample.y));

                var cameraData = renderingData.cameraData;
                m_SSR_WorldToCameraMatrix = cameraData.camera.worldToCameraMatrix;
                m_SSR_CameraToWorldMatrix = cameraData.camera.cameraToWorldMatrix;
                m_SSR_ProjectionMatrix = GL.GetGPUProjectionMatrix(cameraData.camera.projectionMatrix, false);
                m_SSR_ViewProjectionMatrix = m_SSR_ProjectionMatrix * m_SSR_WorldToCameraMatrix;
                m_Material.SetMatrix(m_SSR_ProjectionMatrixID, m_SSR_ProjectionMatrix);
                m_Material.SetMatrix(m_SSR_ViewProjectionMatrixID, m_SSR_ViewProjectionMatrix);
                m_Material.SetMatrix(m_SSR_InvProjectionMatrixID, m_SSR_ProjectionMatrix.inverse);
                m_Material.SetMatrix(m_SSR_InvViewProjectionMatrixID, m_SSR_ViewProjectionMatrix.inverse);
                m_Material.SetMatrix(m_SSR_WorldToCameraMatrixID, m_SSR_WorldToCameraMatrix);
                m_Material.SetMatrix(m_SSR_CameraToWorldMatrixID, m_SSR_CameraToWorldMatrix);
                m_Material.SetMatrix(m_SSR_PrevViewProjectionMatrixID, m_SSR_PrevViewProjectionMatrix);

                Matrix4x4 warpToScreenSpaceMatrix = Matrix4x4.identity;
                warpToScreenSpaceMatrix.m00 = halfCameraSize.x;
                warpToScreenSpaceMatrix.m11 = halfCameraSize.y;
                warpToScreenSpaceMatrix.m03 = halfCameraSize.x;
                warpToScreenSpaceMatrix.m13 = halfCameraSize.y;

                Matrix4x4 projectToPixelMatrix = warpToScreenSpaceMatrix * m_SSR_ProjectionMatrix;
                m_Material.SetMatrix(m_SSR_ProjectToPixelMatrixID, projectToPixelMatrix);

                Vector4 ssrProjInfo = new Vector4(
                    (-2 / (m_ScreenResolution.x * m_SSR_ProjectionMatrix[0])),
                    (-2 / (m_ScreenResolution.y * m_SSR_ProjectionMatrix[5])),
                    (1 - m_SSR_ProjectionMatrix[2]) / m_SSR_ProjectionMatrix[0],
                    (1 - m_SSR_ProjectionMatrix[6]) / m_SSR_ProjectionMatrix[5]
                );
                m_Material.SetVector(m_SSR_ProjectionInfoID, ssrProjInfo);

                // Vector3 clipInfo = float.IsPositiveInfinity(camera.farClipPlane) ? 
                //     new Vector3(camera.nearClipPlane, -1, 1) : 
                //     new Vector3(camera.nearClipPlane * camera.farClipPlane, camera.nearClipPlane - camera.farClipPlane, camera.farClipPlane);
            }

            private float GetHaltonValue(int index, int radix)
            {
                float result = 0.0f;
                float fraction = 1.0f / radix;
                while (index > 0)
                {
                    result += (index % radix) * fraction;
                    index /= radix;
                    fraction /= radix;
                }
                return result;
            }

            private Vector2 GenerateRandomOffset()
            {
                float u = GetHaltonValue(m_SampleIndex % 1023, 2);
                float v = GetHaltonValue(m_SampleIndex % 1023, 3);
                if (m_SampleIndex++ >= k_SampleCount)
                {
                    m_SampleIndex = 0;
                }
                return new Vector2(u, v);
            }
        }
    }
}