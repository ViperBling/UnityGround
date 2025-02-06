using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Experimental.Rendering;

namespace SSR
{
    public partial class SSRFeature
    {
        public class ScreenSpaceReflectionPass : ScriptableRenderPass
        {
            const string m_ProfilingTag = "SSR_RenderReflection";
            
            public SSRResolution m_RenderResolution;
            public SSRMipmapMode m_MipmapMode;

            public ScreenSpaceReflectionEffect m_SSRVolume;
            
            private readonly Material m_SSRMaterial;
            private RTHandle m_SourceHandle;
            private RTHandle m_ReflectHandle;
            
            private static readonly int m_MinSmoothnessID = Shader.PropertyToID("_MinSmoothness");
            private static readonly int m_FadeSmoothnessID = Shader.PropertyToID("_FadeSmoothness");
            private static readonly int m_EdgeFadeID = Shader.PropertyToID("_EdgeFade");
            private static readonly int m_ThicknessID = Shader.PropertyToID("_Thickness");
            private static readonly int m_StepStrideID = Shader.PropertyToID("_StepStride");
            private static readonly int m_MaxStepsID = Shader.PropertyToID("_MaxSteps");
            private static readonly int m_DownSampleID = Shader.PropertyToID("_DownSample");

            public ScreenSpaceReflectionPass(SSRResolution resolution, SSRMipmapMode mipmapMode, Material material)
            {
                m_RenderResolution = resolution;
                m_MipmapMode = mipmapMode;
                m_SSRMaterial = material;
            }

            public void Dispose()
            {
                m_SourceHandle?.Release();
                m_ReflectHandle?.Release();
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.useMipMap = false;
                
                // Approximation mode
                RenderingUtils.ReAllocateIfNeeded(ref m_SourceHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_SSRSourceTexture");
                desc.width = (int)m_RenderResolution * (int)(desc.width * 0.25f);
                desc.height = (int)m_RenderResolution * (int)(desc.height * 0.25f);
                desc.useMipMap = (m_MipmapMode == SSRMipmapMode.TriLinear);
                FilterMode filterMode = (m_MipmapMode == SSRMipmapMode.TriLinear) ? FilterMode.Trilinear : FilterMode.Point;

                RenderingUtils.ReAllocateIfNeeded(ref m_ReflectHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRReflectionColorTexture");
                ConfigureInput(ScriptableRenderPassInput.Depth);
                
                ConfigureTarget(m_SourceHandle, m_SourceHandle);
            }
            
            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                m_SourceHandle = null;
                m_ReflectHandle = null;
            }

            public override void FrameCleanup(CommandBuffer cmd)
            {
                if (m_SourceHandle != null)
                {
                    cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_SourceHandle.name));
                }
                if (m_ReflectHandle != null)
                {
                    cmd.ReleaseTemporaryRT(Shader.PropertyToID(m_ReflectHandle.name));
                }
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get("ScreenSpaceReflection");
                using (new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag)))
                {
                    if (m_SSRVolume.m_Quality.value == ScreenSpaceReflectionEffect.SSRQuality.Low)
                    {
                        m_SSRMaterial.SetFloat(m_StepStrideID, 0.4f);
                        m_SSRMaterial.SetFloat(m_MaxStepsID, 32);
                    }
                    else if (m_SSRVolume.m_Quality.value == ScreenSpaceReflectionEffect.SSRQuality.Medium)
                    {
                        m_SSRMaterial.SetFloat(m_StepStrideID, 0.3f);
                        m_SSRMaterial.SetFloat(m_MaxStepsID, 64);
                    }
                    else if (m_SSRVolume.m_Quality.value == ScreenSpaceReflectionEffect.SSRQuality.High)
                    {
                        m_SSRMaterial.SetFloat(m_StepStrideID, 0.1f);
                        m_SSRMaterial.SetFloat(m_MaxStepsID, 128);
                    }
                    else
                    {
                        m_SSRMaterial.SetFloat(m_StepStrideID, 0.1f);
                        m_SSRMaterial.SetFloat(m_MaxStepsID, m_SSRVolume.m_MaxStep.value);
                    }

                    m_SSRMaterial.SetFloat(m_MinSmoothnessID, m_SSRVolume.m_MinSmoothness.value);
                    m_SSRMaterial.SetFloat(m_FadeSmoothnessID, m_SSRVolume.m_FadeSmoothness.value);
                    m_SSRMaterial.SetFloat(m_EdgeFadeID, m_SSRVolume.m_EdgeFade.value);
                    m_SSRMaterial.SetFloat(m_ThicknessID, m_SSRVolume.m_ObjThickness.value);
                    m_SSRMaterial.SetFloat(m_DownSampleID, (int)m_RenderResolution * 0.25f);

                    if (m_MipmapMode == SSRMipmapMode.TriLinear)
                    {
                        m_SSRMaterial.EnableKeyword("_SSR_APPROX_COLOR_MIPMAP");
                    }
                    else
                    {
                        m_SSRMaterial.DisableKeyword("_SSR_APPROX_COLOR_MIPMAP");
                    }
                    
                    Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, m_SourceHandle);
                    Blitter.BlitCameraTexture(cmd, m_SourceHandle, m_ReflectHandle, m_SSRMaterial, pass : 0);
                    Blitter.BlitCameraTexture(cmd, m_ReflectHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_SSRMaterial, pass : 1);
                }
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }
        }

        public class BackFaceDepthPass : ScriptableRenderPass
        {
            const string m_ProfilingTag = "SSR_RenderBackFaceDepth";
            private readonly Material m_SSRMaterial;
            public ScreenSpaceReflectionEffect m_SSRVolume;
            private RTHandle m_BackFaceDepthHandle;

            private RenderStateBlock m_DepthRenderStateBlock = new(RenderStateMask.Nothing);
            
            public BackFaceDepthPass(Material material)
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
                
                RenderingUtils.ReAllocateIfNeeded(ref m_BackFaceDepthHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name : "_SSRCameraBackFaceDepthTexture");
                cmd.SetGlobalTexture("_SSRCameraBackFaceDepthTexture", m_BackFaceDepthHandle);
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
                if (m_SSRVolume.m_ThicknessMode.value == ScreenSpaceReflectionEffect.ThicknessMode.ComputeBackface)
                {
                    CommandBuffer cmd = CommandBufferPool.Get("ScreenSpaceReflection");
                    using (new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag)))
                    {
                        // 只存Depth
                        cmd.SetRenderTarget(m_BackFaceDepthHandle,
                            RenderBufferLoadAction.DontCare,
                            RenderBufferStoreAction.DontCare,
                            m_BackFaceDepthHandle,
                            RenderBufferLoadAction.DontCare,
                            RenderBufferStoreAction.Store);
                        cmd.ClearRenderTarget(clearDepth : true, clearColor : true, Color.clear);

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
                        
                        m_SSRMaterial.EnableKeyword("_BACKFACE_ENABLED");
                    }
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    CommandBufferPool.Release(cmd);
                }
                else
                {
                    m_SSRMaterial.DisableKeyword("_BACKFACE_ENABLED");
                }
            }
        }
    }
}