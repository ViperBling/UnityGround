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

            public ScreenSpaceReflectionEffect m_SSRVolume;
            
            private static int m_Frame = 0; // Frame counter

            private readonly Material m_Material;
            private RTHandle m_SceneColorHandle;
            private RTHandle m_ReflectColorHandle;
            private RTHandle m_TemporalCurrentHandle;
            private RTHandle m_TemporalHistoryHandle;
            private RTHandle m_TempHandle;

            private static readonly int m_FrameID = Shader.PropertyToID("_Frame");
            private static readonly int m_MinSmoothnessID = Shader.PropertyToID("_MinSmoothness");
            private static readonly int m_FadeSmoothnessID = Shader.PropertyToID("_FadeSmoothness");
            private static readonly int m_EdgeFadeID = Shader.PropertyToID("_EdgeFade");
            private static readonly int m_ThicknessScaleID = Shader.PropertyToID("_ThicknessScale");
            private static readonly int m_StepStrideID = Shader.PropertyToID("_StepStride");
            private static readonly int m_MaxStepsID = Shader.PropertyToID("_MaxSteps");
            private static readonly int m_WorldSpaceViewDirID = Shader.PropertyToID("_WorldSpaceViewDir");
            private static readonly int m_SSRJitterID = Shader.PropertyToID("_SSRJitter");
            private static readonly int m_ScreenResolutionID = Shader.PropertyToID("_ScreenResolution");
            private static readonly int m_BlueNoiseTextureID = Shader.PropertyToID("_BlueNoiseTexture");
            private static readonly int m_BRDFLUTID = Shader.PropertyToID("_BRDFLUT");
            private static readonly int m_ReflectSkyID = Shader.PropertyToID("_ReflectSky");
            private static readonly int m_PrevViewProjMatrixID = Shader.PropertyToID("_PrevViewProjMatrix");
            private static readonly int m_BRDFBiasID = Shader.PropertyToID("_BRDFBias");
            private const int m_LinearSSTracingPass = 0;
            private const int m_HiZTracingPass = 1;
            private const int m_SpatioFilterPass = 2;
            private const int m_TemporalFilterPass = 3;
            private const int m_CompositePass = 2;

            private bool m_IsPadded = false;
            private float m_Scale;
            private Vector2 m_ScreenResolution;
            private Matrix4x4 m_PrevViewProjMatrix = Matrix4x4.identity;
        
            private int m_SampleIndex = 0;
            private const int k_SampleCount = 64;
            private Vector2 m_RandomSample;

            public ScreenSpaceReflectionPass(Material material)
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
                // if (m_Material == null) return;
                base.Configure(cmd, cameraRTDesc);

                m_Material.SetInt(m_FrameID, m_Frame);
                m_Material.SetTexture(m_BlueNoiseTextureID, m_SSRVolume.m_BlueNoiseTexture.value);
                m_Material.SetTexture(m_BRDFLUTID, m_SSRVolume.m_BRDFLUT.value);

                m_IsPadded = m_SSRVolume.m_MarchingMode == ScreenSpaceReflectionEffect.RayMarchingMode.HiZTracing;
                m_Scale = m_IsPadded ? 1 : m_SSRVolume.m_DownSample.value + 1.0f;
                m_RandomSample = GenerateRandomOffset();

                float globalResolution = 1.0f / m_Scale;

                m_ScreenResolution.x = cameraRTDesc.width * globalResolution;
                m_ScreenResolution.y = cameraRTDesc.height * globalResolution;

                m_Material.SetVector(m_ScreenResolutionID, new Vector4(m_ScreenResolution.x, m_ScreenResolution.y, 1.0f / m_ScreenResolution.x, 1.0f / m_ScreenResolution.y));

                SetMaterialProperties();
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.useMipMap = true;
                desc.colorFormat = RenderTextureFormat.ARGBFloat;

                FilterMode filterMode = FilterMode.Bilinear;
                RenderingUtils.ReAllocateIfNeeded(ref m_SceneColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRSceneColorTexture");
                filterMode = FilterMode.Point;
                desc.useMipMap = false;
                RenderingUtils.ReAllocateIfNeeded(ref m_ReflectColorHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRReflectionColorTexture");
                RenderingUtils.ReAllocateIfNeeded(ref m_TemporalCurrentHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRTemporalCurrentTexture");
                RenderingUtils.ReAllocateIfNeeded(ref m_TemporalHistoryHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRTemporalHistoryTexture");
                RenderingUtils.ReAllocateIfNeeded(ref m_TempHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_SSRTempTexture");
                
                ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Motion);
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
                // if (m_Material == null) return;

                CommandBuffer cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, new ProfilingSampler(m_ProfilingTag)))
                {
                    m_Material.SetVector(m_WorldSpaceViewDirID, renderingData.cameraData.camera.transform.forward);

                    var renderCameraData = renderingData.cameraData;
                    Matrix4x4 currVPMat = renderCameraData.GetGPUProjectionMatrix() * renderCameraData.GetViewMatrix();
                    cmd.SetGlobalMatrix(m_PrevViewProjMatrixID, m_PrevViewProjMatrix);

                    // 1. 获取SceneColor
                    Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, m_SceneColorHandle);

                    // 2. 利用SceneColor进行反射计算，得到HitUV、Mask
                    if (m_SSRVolume.m_MarchingMode == ScreenSpaceReflectionEffect.RayMarchingMode.LinearScreenSpaceTracing)
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: m_LinearSSTracingPass);
                    }
                    else
                    {
                        Blitter.BlitCameraTexture(cmd, m_SceneColorHandle, m_ReflectColorHandle, m_Material, pass: m_HiZTracingPass);
                    }

                    // 3. 利用Hit数据进行空间滤波
                    // cmd.SetGlobalTexture(m_SceneColorHandle.name, m_SceneColorHandle);
                    // Blitter.BlitCameraTexture(cmd, m_ReflectColorHandle, m_TemporalCurrentHandle, m_Material, pass: m_SpatioFilterPass);

                    // bool useTemporalFiltering = m_SSRVolume.m_UseTemporalFilter.value;
                    // // 4. Temporal Filter
                    // if (useTemporalFiltering)
                    // {
                    //     cmd.SetGlobalTexture(m_ReflectColorHandle.name, m_ReflectColorHandle);
                    //     cmd.SetGlobalTexture(m_TemporalHistoryHandle.name, m_TemporalHistoryHandle);
                    //     Blitter.BlitCameraTexture(cmd, m_TemporalCurrentHandle, m_TempHandle, m_Material, pass: m_TemporalFilterPass);
                    //     cmd.CopyTexture(m_TempHandle, m_TemporalHistoryHandle);

                    //     Blitter.BlitCameraTexture(cmd, m_TempHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass: m_CompositePass);
                    // }
                    // else
                    // {
                    //     Blitter.BlitCameraTexture(cmd, m_TemporalCurrentHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass: m_CompositePass);
                    // }
                    // m_FirstFrame = false;

                    Blitter.BlitCameraTexture(cmd, m_ReflectColorHandle, renderingData.cameraData.renderer.cameraColorTargetHandle, m_Material, pass: m_CompositePass);

                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    CommandBufferPool.Release(cmd);
                    m_PrevViewProjMatrix = currVPMat;
                }
            }

            private void SetMaterialProperties()
            {
                if (m_SSRVolume.m_DitherMode == ScreenSpaceReflectionEffect.DitherMode.Disabled)
                {
                    m_Material.DisableKeyword("DITHER_8x8");
                    m_Material.DisableKeyword("DITHER_INTERLEAVED_GRADIENT");
                }
                else if (m_SSRVolume.m_DitherMode == ScreenSpaceReflectionEffect.DitherMode.Dither8x8)
                {
                    m_Material.EnableKeyword("DITHER_8x8");
                }
                else if (m_SSRVolume.m_DitherMode == ScreenSpaceReflectionEffect.DitherMode.InterleavedGradient)
                {
                    m_Material.EnableKeyword("DITHER_INTERLEAVED_GRADIENT");
                }
                
                m_Material.SetFloat(m_MinSmoothnessID, m_SSRVolume.m_MinSmoothness.value);
                m_Material.SetFloat(m_FadeSmoothnessID, m_SSRVolume.m_FadeSmoothness.value);
                m_Material.SetFloat(m_EdgeFadeID, m_SSRVolume.m_EdgeFade.value);
                m_Material.SetFloat(m_ThicknessScaleID, m_SSRVolume.m_ThicknessScale.value);
                m_Material.SetFloat(m_StepStrideID, m_SSRVolume.m_StepStrideLength.value);
                m_Material.SetFloat(m_MaxStepsID, m_SSRVolume.m_MaxSteps.value);
                m_Material.SetFloat(m_BRDFBiasID, m_SSRVolume.m_BRDFBias.value);
                m_Material.SetInt(m_ReflectSkyID, m_SSRVolume.m_ReflectSky.value ? 1 : 0);
                m_Material.SetVector(m_SSRJitterID, new Vector4(m_ScreenResolution.x / 1024.0f, m_ScreenResolution.y / 1024.0f, m_RandomSample.x, m_RandomSample.y));
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