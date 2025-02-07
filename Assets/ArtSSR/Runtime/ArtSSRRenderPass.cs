using System;
using UnityEngine;
using UnityEngine.Rendering;
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
            
            private Material m_Material;
            private RTHandle m_SceneColorHandle;
            private RTHandle m_ReflectColorHandle;
            
            private static readonly int m_MinSmoothnessID = Shader.PropertyToID("_MinSmoothness");
            // private static readonly int m_FadeSmoothnessID = Shader.PropertyToID("_FadeSmoothness");
            private static readonly int m_EdgeFadeID = Shader.PropertyToID("_EdgeFade");
            // private static readonly int m_ThicknessID = Shader.PropertyToID("_Thickness");
            private static readonly int m_StepStrideID = Shader.PropertyToID("_StepStride");
            private static readonly int m_MaxStepsID = Shader.PropertyToID("_MaxSteps");
            private static readonly int m_WorldSpaceViewDirID = Shader.PropertyToID("_WorldSpaceViewDir");
            // private static readonly int m_DownSampleID = Shader.PropertyToID("_DownSample");

            private bool m_IsPadded = false;
            
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
                base.Configure(cmd, cameraRTDesc);
            
                m_Material.SetInt("_Frame", m_Frame);

                m_IsPadded = m_SSRVolume.m_MarchingMode == ArtSSREffect.RayMarchingMode.HiZTracing;

                if (m_SSRVolume.m_DitherMode == ArtSSREffect.DitherMode.Disabled)
                {
                    m_Material.DisableKeyword("DITHER_8x8");
                    m_Material.DisableKeyword("DITHER_INTERLEAVED_GRADIENT");
                }
                else if (m_SSRVolume.m_DitherMode == ArtSSREffect.DitherMode.Dither8x8)
                {
                    m_Material.EnableKeyword("DITHER_8x8");
                }
                else
                {
                    m_Material.EnableKeyword("DITHER_INTERLEAVED_GRADIENT");
                }
                
                // if (m_IsPadded)
                // {
                //     m_ScreenWidth = cameraRTDesc.width;
                //     m_ScreenHeight = cameraRTDesc.height * GlobalArtSSRSettings.GlobalResolutionScale;
                //     m_PaddedScreenWidth = Mathf.NextPowerOfTwo((int)m_ScreenWidth);
                //     m_PaddedScreenHeight = Mathf.NextPowerOfTwo((int)m_ScreenHeight);
                // }
                // else
                // {
                //     m_ScreenWidth = cameraRTDesc.width;
                //     m_ScreenHeight = cameraRTDesc.height;
                //     m_PaddedScreenWidth = m_ScreenWidth / m_Scale;
                //     m_PaddedScreenHeight = m_ScreenHeight / m_Scale;
                // }
                
                // Vector2 screenResolution = new Vector2(m_ScreenWidth, m_ScreenHeight);
                // m_Settings.m_SSRMaterial.SetVector("_ScreenResolution", screenResolution);
                // if (m_IsPadded)
                // {
                //     Vector2 paddedResolution = new Vector2(m_PaddedScreenWidth, m_PaddedScreenHeight);
                //     m_PaddedScale = paddedResolution / screenResolution;
                //     m_Settings.m_SSRMaterial.SetVector("_PaddedResolution", paddedResolution);
                //     m_Settings.m_SSRMaterial.SetVector("_PaddedScale", m_PaddedScale);
                //
                //     float cX = 1.0f / (512.0f * paddedResolution.x);
                //     float cY = 1.0f / (512.0f * paddedResolution.y);
                //     
                //     m_Settings.m_SSRMaterial.SetVector("_CrossEpsilon", new Vector2(cX, cY));
                // }
                // else
                // {
                //     m_PaddedScale = Vector2.one;
                //     m_Settings.m_SSRMaterial.SetVector("_PaddedScale", m_PaddedScale);
                // }
                
                // cmdBuffer.GetTemporaryRT(m_ReflectionMapID, Mathf.CeilToInt(m_PaddedScreenWidth), Mathf.CeilToInt(m_PaddedScreenHeight), 0, FilterMode.Point, RenderTextureFormat.ARGBHalf);
                
                // m_TempPaddedSceneColorID = Shader.PropertyToID("_TempPaddedSceneColor");
                // int tX = m_IsPadded ? Mathf.NextPowerOfTwo(cameraRTDesc.width) : cameraRTDesc.width;
                // int tY = m_IsPadded ? Mathf.NextPowerOfTwo(cameraRTDesc.height) : cameraRTDesc.height;
                // cameraRTDesc.width = tX;
                // cameraRTDesc.height = tY;
                // cmdBuffer.GetTemporaryRT(m_TempPaddedSceneColorID, cameraRTDesc, FilterMode.Trilinear);
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.useMipMap = false;
                
                // Approximation mode
                RenderingUtils.ReAllocateIfNeeded(ref m_SceneColorHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_ArtSSRSourceTexture");
                desc.useMipMap = false;
                FilterMode filterMode = FilterMode.Point;

                RenderingUtils.ReAllocateIfNeeded(ref m_ReflectColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_ArtSSRReflectionColorTexture");
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
                
                using var newProfile = new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag));
                
                m_Material.SetFloat(m_MinSmoothnessID, m_SSRVolume.m_MinSmoothness.value);
                m_Material.SetFloat(m_EdgeFadeID, m_SSRVolume.m_EdgeFade.value);
                m_Material.SetFloat(m_StepStrideID, m_SSRVolume.m_StepStrideLength.value);
                m_Material.SetFloat(m_MaxStepsID, m_SSRVolume.m_MaxSteps.value);
                m_Material.SetVector(m_WorldSpaceViewDirID, renderingData.cameraData.camera.transform.forward);
                
                const int linearPass = 0;
                const int hiZPass = 1;
                const int compositePass = 2;

                Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, m_SceneColorHandle);
                
                if (m_SSRVolume.m_MarchingMode == ArtSSREffect.RayMarchingMode.HiZTracing)
                {
                    Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass : hiZPass);
                }
                else
                {
                    Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass : linearPass);
                }
                
                Blitter.BlitCameraTexture(cmd, m_ReflectColorHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass : compositePass);
                
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }
            
            // private static int m_Frame = 0; // Frame counter
            //
            // public RenderTargetIdentifier m_ColorSource { get; internal set; }
            // private int m_ReflectionMapID;
            // private int m_TempPaddedSceneColorID;
            //
            // internal SSRSettings m_Settings { get; set; }
            //
            // internal float m_RenderScale { get; set; }
            //
            // private float m_PaddedScreenWidth;
            // private float m_PaddedScreenHeight;
            // private float m_ScreenWidth;
            // private float m_ScreenHeight;
            // private Vector2 m_PaddedScale;
            // private bool m_IsPadded => m_Settings.m_TracingMode == RayTracingMode.HiZTracing;
            // private float m_Scale => m_Settings.m_DownSample + 1;
            //
            // public override void Configure(CommandBuffer cmdBuffer, RenderTextureDescriptor cameraRTDesc)
            // {
            //     base.Configure(cmdBuffer, cameraRTDesc);
            //     
            //     m_Settings.m_SSRMaterial.SetInt("_Frame", m_Frame);
            //     if (m_Settings.m_DitherMode == DitherMode.InterleavedGradient)
            //     {
            //         m_Settings.m_SSRMaterial.SetInt("_DitherMode", 1);
            //     }
            //     else
            //     {
            //         m_Settings.m_SSRMaterial.SetInt("_DitherMode", 0);
            //     }
            //     GlobalArtSSRSettings.GlobalResolutionScale = 1.0f / m_Scale;
            //     if (m_IsPadded)
            //     {
            //         m_ScreenWidth = cameraRTDesc.width * GlobalArtSSRSettings.GlobalResolutionScale;
            //         m_ScreenHeight = cameraRTDesc.height * GlobalArtSSRSettings.GlobalResolutionScale;
            //         m_PaddedScreenWidth = Mathf.NextPowerOfTwo((int)m_ScreenWidth);
            //         m_PaddedScreenHeight = Mathf.NextPowerOfTwo((int)m_ScreenHeight);
            //     }
            //     else
            //     {
            //         m_ScreenWidth = cameraRTDesc.width;
            //         m_ScreenHeight = cameraRTDesc.height;
            //         m_PaddedScreenWidth = m_ScreenWidth / m_Scale;
            //         m_PaddedScreenHeight = m_ScreenHeight / m_Scale;
            //     }
            //
            //     cameraRTDesc.colorFormat = RenderTextureFormat.DefaultHDR;
            //     cameraRTDesc.mipCount = 8;
            //     cameraRTDesc.autoGenerateMips = true;
            //     cameraRTDesc.useMipMap = true;
            //     
            //     m_ReflectionMapID = Shader.PropertyToID("_ReflectedColorMap");
            //
            //     Vector2 screenResolution = new Vector2(m_ScreenWidth, m_ScreenHeight);
            //     m_Settings.m_SSRMaterial.SetVector("_ScreenResolution", screenResolution);
            //     if (m_IsPadded)
            //     {
            //         Vector2 paddedResolution = new Vector2(m_PaddedScreenWidth, m_PaddedScreenHeight);
            //         m_PaddedScale = paddedResolution / screenResolution;
            //         m_Settings.m_SSRMaterial.SetVector("_PaddedResolution", paddedResolution);
            //         m_Settings.m_SSRMaterial.SetVector("_PaddedScale", m_PaddedScale);
            //
            //         float cX = 1.0f / (512.0f * paddedResolution.x);
            //         float cY = 1.0f / (512.0f * paddedResolution.y);
            //         
            //         m_Settings.m_SSRMaterial.SetVector("_CrossEpsilon", new Vector2(cX, cY));
            //     }
            //     else
            //     {
            //         m_PaddedScale = Vector2.one;
            //         m_Settings.m_SSRMaterial.SetVector("_PaddedScale", m_PaddedScale);
            //     }
            //     
            //     cmdBuffer.GetTemporaryRT(m_ReflectionMapID, Mathf.CeilToInt(m_PaddedScreenWidth), Mathf.CeilToInt(m_PaddedScreenHeight), 0, FilterMode.Point, RenderTextureFormat.ARGBHalf);
            //     
            //     m_TempPaddedSceneColorID = Shader.PropertyToID("_TempPaddedSceneColor");
            //     int tX = m_IsPadded ? Mathf.NextPowerOfTwo(cameraRTDesc.width) : cameraRTDesc.width;
            //     int tY = m_IsPadded ? Mathf.NextPowerOfTwo(cameraRTDesc.height) : cameraRTDesc.height;
            //     cameraRTDesc.width = tX;
            //     cameraRTDesc.height = tY;
            //     cmdBuffer.GetTemporaryRT(m_TempPaddedSceneColorID, cameraRTDesc, FilterMode.Trilinear);
            // }
            //
            // public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            // {
            //     const int linearPass = 0;
            //     const int hiZPass = 1;
            //     const int compositePass = 2;
            //     
            //     CommandBuffer cmdBuffer = CommandBufferPool.Get("ArtSSR");
            //     cmdBuffer.Blit(m_ColorSource, m_TempPaddedSceneColorID, m_PaddedScale, Vector2.zero);
            //     
            //     // Calculate the reflection
            //     if (m_Settings.m_TracingMode == RayTracingMode.HiZTracing)
            //     {
            //         cmdBuffer.Blit(null, m_ReflectionMapID, m_Settings.m_SSRMaterial, hiZPass);
            //     }
            //     else
            //     {
            //         cmdBuffer.Blit(null, m_ReflectionMapID, m_Settings.m_SSRMaterial, linearPass);
            //     }
            //     
            //     // Composite the reflection
            //     cmdBuffer.Blit(m_TempPaddedSceneColorID, m_ColorSource, m_Settings.m_SSRMaterial, compositePass);
            //     
            //     cmdBuffer.ReleaseTemporaryRT(m_ReflectionMapID);
            //     cmdBuffer.ReleaseTemporaryRT(m_TempPaddedSceneColorID);
            //     
            //     context.ExecuteCommandBuffer(cmdBuffer);
            //     CommandBufferPool.Release(cmdBuffer);
            // }
            //
            // public override void FrameCleanup(CommandBuffer cmd)
            // {
            //     cmd.ReleaseTemporaryRT(m_ReflectionMapID);
            //     cmd.ReleaseTemporaryRT(m_TempPaddedSceneColorID);
            //     m_Frame++;
            // }
            //
            // public override void OnCameraCleanup(CommandBuffer cmdBuffer)
            // {
            //     
            // }
        }
    }
    
}