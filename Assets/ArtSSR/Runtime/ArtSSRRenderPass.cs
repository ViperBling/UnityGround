﻿using System;
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
            private const string m_ProfilingTag = "ArtSSR_RenderReflection";

            public ArtSSREffect m_SSRVolume;

            private static int m_Frame = 0; // Frame counter

            private readonly Material m_Material;
            private RTHandle m_SceneColorHandle;
            private RTHandle m_ReflectColorHandle;

            private static readonly int m_FrameID = Shader.PropertyToID("_Frame");
            private static readonly int m_MinSmoothnessID = Shader.PropertyToID("_MinSmoothness");
            private static readonly int m_FadeSmoothnessID = Shader.PropertyToID("_FadeSmoothness");
            private static readonly int m_EdgeFadeID = Shader.PropertyToID("_EdgeFade");
            private static readonly int m_ThicknessScaleID = Shader.PropertyToID("_ThicknessScale");
            private static readonly int m_StepStrideID = Shader.PropertyToID("_StepStride");
            private static readonly int m_MaxStepsID = Shader.PropertyToID("_MaxSteps");
            private static readonly int m_WorldSpaceViewDirID = Shader.PropertyToID("_WorldSpaceViewDir");
            private static readonly int m_DownSampleID = Shader.PropertyToID("_DownSample");
            private static readonly int m_ScreenResolutionID = Shader.PropertyToID("_ScreenResolution");
            private static readonly int m_ReflectSkyID = Shader.PropertyToID("_ReflectSky");

            private bool m_IsPadded = false;
            private float m_Scale;
            private Vector2 m_ScreenResolution;

            public ArtSSRRenderPass(Material material)
            {
                m_Material = material;
            }

            public void Dispose()
            {
                m_SceneColorHandle?.Release();
                m_ReflectColorHandle?.Release();
            }

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraRTDesc)
            {
                if (m_Material == null) return;
                base.Configure(cmd, cameraRTDesc);

                m_Material.SetInt(m_FrameID, m_Frame);

                m_IsPadded = m_SSRVolume.m_MarchingMode == ArtSSREffect.RayMarchingMode.HiZTracing;
                m_Scale = m_IsPadded ? 1 : m_SSRVolume.m_DownSample.value + 1.0f;

                float globalResolution = 1.0f / m_Scale;

                m_ScreenResolution.x = cameraRTDesc.width * globalResolution;
                m_ScreenResolution.y = cameraRTDesc.height * globalResolution;

                m_Material.SetVector(m_ScreenResolutionID, m_ScreenResolution);
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.useMipMap = true;

                FilterMode filterMode = FilterMode.Bilinear;
                RenderingUtils.ReAllocateIfNeeded(ref m_SceneColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRSceneColorTexture");
                desc.useMipMap = false;
                filterMode = FilterMode.Point;

                RenderingUtils.ReAllocateIfNeeded(ref m_ReflectColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRReflectionColorTexture");
                ConfigureInput(ScriptableRenderPassInput.Depth);

                ConfigureTarget(m_SceneColorHandle, m_SceneColorHandle);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                m_SceneColorHandle = null;
                m_ReflectColorHandle = null;
            }

            public override void FrameCleanup(CommandBuffer cmd)
            {
                if (m_SceneColorHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_SceneColorHandle.name));
                if (m_ReflectColorHandle != null) cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_ReflectColorHandle.name));
                m_Frame++;
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get("ArtSSR");
                if (m_Material == null) return;
                using (new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag)))
                {
                    SetMaterialProperties(ref renderingData);

                    const int linearPass = 0;
                    const int hiZPass = 1;
                    const int ssTracingPass = 2;
                    const int compositePass = 3;

                    Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, m_SceneColorHandle);

                    cmd.SetGlobalTexture(m_SceneColorHandle.name, m_SceneColorHandle);

                    if (m_SSRVolume.m_MarchingMode == ArtSSREffect.RayMarchingMode.HiZTracing)
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: hiZPass);
                    }
                    else if (m_SSRVolume.m_MarchingMode == ArtSSREffect.RayMarchingMode.ScreenSpaceTracing)
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: ssTracingPass);
                    }
                    else
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: linearPass);
                    }
                    Blitter.BlitCameraTexture(cmd, m_ReflectColorHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass: compositePass);

                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    CommandBufferPool.Release(cmd);
                }
            }

            private void SetMaterialProperties(ref RenderingData renderingData)
            {
                if (m_SSRVolume.m_DitherMode == ArtSSREffect.DitherMode.Disabled)
                {
                    m_Material.DisableKeyword("DITHER_8x8");
                    m_Material.DisableKeyword("DITHER_INTERLEAVED_GRADIENT");
                }
                else if (m_SSRVolume.m_DitherMode == ArtSSREffect.DitherMode.Dither8x8)
                {
                    m_Material.EnableKeyword("DITHER_8x8");
                }
                else if (m_SSRVolume.m_DitherMode == ArtSSREffect.DitherMode.InterleavedGradient)
                {
                    m_Material.EnableKeyword("DITHER_INTERLEAVED_GRADIENT");
                }
                
                m_Material.SetFloat(m_MinSmoothnessID, m_SSRVolume.m_MinSmoothness.value);
                m_Material.SetFloat(m_FadeSmoothnessID, m_SSRVolume.m_FadeSmoothness.value);
                m_Material.SetFloat(m_EdgeFadeID, m_SSRVolume.m_EdgeFade.value);
                m_Material.SetFloat(m_ThicknessScaleID, m_SSRVolume.m_ThicknessScale.value);
                m_Material.SetFloat(m_StepStrideID, m_SSRVolume.m_StepStrideLength.value);
                m_Material.SetFloat(m_MaxStepsID, m_SSRVolume.m_MaxSteps.value);
                m_Material.SetVector(m_WorldSpaceViewDirID, renderingData.cameraData.camera.transform.forward);
                m_Material.SetInt(m_ReflectSkyID, m_SSRVolume.m_ReflectSky.value ? 1 : 0);
            }
        }

        internal class ArtSSRBackFaceDepthPass : ScriptableRenderPass
        {
            const string m_ProfilingTag = "ArtSSR_RenderBackFaceDepth";
            private readonly Material m_SSRMaterial;
            public ArtSSREffect m_SSRVolume;
            private RTHandle m_BackFaceDepthHandle;

            private RenderStateBlock m_DepthRenderStateBlock = new(RenderStateMask.Nothing);

            private static readonly int m_SSRBackFaceDepthID = Shader.PropertyToID("_SSRCameraBackFaceDepthTexture");

            public ArtSSRBackFaceDepthPass(Material material)
            {
                m_SSRMaterial = material;
            }

            public void Dispose()
            {
                m_BackFaceDepthHandle?.Release();
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;

                RenderingUtils.ReAllocateIfNeeded(ref m_BackFaceDepthHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_SSRCameraBackFaceDepthTexture");
                cmd.SetGlobalTexture(m_SSRBackFaceDepthID, m_BackFaceDepthHandle);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                m_BackFaceDepthHandle = null;
            }

            public override void FrameCleanup(CommandBuffer cmd)
            {
                if (m_BackFaceDepthHandle != null)
                {
                    cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_BackFaceDepthHandle.name));
                }
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get("ArtSSR");
                using (new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag)))
                {
                    // 只存Depth
                    cmd.SetRenderTarget(m_BackFaceDepthHandle,
                        RenderBufferLoadAction.DontCare,
                        RenderBufferStoreAction.DontCare,
                        m_BackFaceDepthHandle,
                        RenderBufferLoadAction.DontCare,
                        RenderBufferStoreAction.Store);
                    cmd.ClearRenderTarget(clearDepth: true, clearColor: true, Color.clear);

                    RendererListDesc rendererListDesc = new(new ShaderTagId("DepthOnly"), renderingData.cullResults, renderingData.cameraData.camera);
                    m_DepthRenderStateBlock.depthState = new DepthState(true, CompareFunction.LessEqual);
                    m_DepthRenderStateBlock.mask |= RenderStateMask.Depth;
                    m_DepthRenderStateBlock.rasterState = new RasterState(CullMode.Front);
                    m_DepthRenderStateBlock.mask |= RenderStateMask.Raster;

                    rendererListDesc.stateBlock = m_DepthRenderStateBlock;
                    rendererListDesc.sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                    rendererListDesc.renderQueueRange = RenderQueueRange.opaque;
                    RendererList rendererList = context.CreateRendererList(rendererListDesc);

                    cmd.DrawRendererList(rendererList);
                }
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }
        }
    }

}