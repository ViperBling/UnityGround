using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ArtSSR
{
    public partial class ArtSSRRenderFeature
    {
        [ExecuteAlways]
        internal class ArtSSRRenderPass : ScriptableRenderPass
        {
            private static int m_Frame = 0; // Frame counter
            public RenderTargetIdentifier m_ColorSource { get; internal set; }
            private int m_ReflectionMapID;
            private int m_TempPaddedDepthID;
        
            internal SSRSettings m_Settings { get; set; }
            
            internal float m_RenderScale { get; set; }

            private float m_PaddedScreenWidth;
            private float m_PaddedScreenHeight;
            private float m_ScreenWidth;
            private float m_ScreenHeight;
            private Vector2 m_PaddedScale;
            private bool m_IsPadded => m_Settings.m_TracingMode == RayTracingMode.HiZTracing;
            private float m_Scale => m_Settings.m_DownSample + 1;

            public override void Configure(CommandBuffer cmdBuffer, RenderTextureDescriptor cameraRTDesc)
            {
                base.Configure(cmdBuffer, cameraRTDesc);
                
                m_Settings.m_SSRMaterial.SetInt("_Frame", m_Frame);
                if (m_Settings.m_DitherMode == DitherMode.InterleavedGradient)
                {
                    m_Settings.m_SSRMaterial.SetInt("_DitherMode", 1);
                }
                else
                {
                    m_Settings.m_SSRMaterial.SetInt("_DitherMode", 0);
                }
                GlobalArtSSRSettings.GlobalResolutionScale = 1.0f / m_Scale;
                if (m_IsPadded)
                {
                    m_ScreenWidth = cameraRTDesc.width * GlobalArtSSRSettings.GlobalResolutionScale;
                    m_ScreenHeight = cameraRTDesc.height * GlobalArtSSRSettings.GlobalResolutionScale;
                    m_PaddedScreenWidth = Mathf.NextPowerOfTwo((int)m_ScreenWidth);
                    m_PaddedScreenHeight = Mathf.NextPowerOfTwo((int)m_ScreenHeight);
                }
                else
                {
                    m_ScreenWidth = cameraRTDesc.width;
                    m_ScreenHeight = cameraRTDesc.height;
                    m_PaddedScreenWidth = m_ScreenWidth / m_Scale;
                    m_PaddedScreenHeight = m_ScreenHeight / m_Scale;
                }

                cameraRTDesc.colorFormat = RenderTextureFormat.DefaultHDR;
                cameraRTDesc.mipCount = 8;
                cameraRTDesc.autoGenerateMips = true;
                cameraRTDesc.useMipMap = true;
                
                m_ReflectionMapID = Shader.PropertyToID("_ReflectedColorMap");

                Vector2 screenResolution = new Vector2(m_ScreenWidth, m_ScreenHeight);
                m_Settings.m_SSRMaterial.SetVector("_ScreenResolution", screenResolution);
                if (m_IsPadded)
                {
                    Vector2 paddedResolution = new Vector2(m_PaddedScreenWidth, m_PaddedScreenHeight);
                    m_PaddedScale = paddedResolution / screenResolution;
                    m_Settings.m_SSRMaterial.SetVector("_PaddedResolution", paddedResolution);
                    m_Settings.m_SSRMaterial.SetVector("_PaddedScale", m_PaddedScale);

                    float cX = 1.0f / (512.0f * paddedResolution.x);
                    float cY = 1.0f / (512.0f * paddedResolution.y);
                    
                    m_Settings.m_SSRMaterial.SetVector("_CrossEpsilon", new Vector2(cX, cY));
                }
                else
                {
                    m_PaddedScale = Vector2.one;
                    m_Settings.m_SSRMaterial.SetVector("_PaddedScale", m_PaddedScale);
                }
                
                cmdBuffer.GetTemporaryRT(m_ReflectionMapID, Mathf.CeilToInt(m_PaddedScreenWidth), Mathf.CeilToInt(m_PaddedScreenHeight), 0, FilterMode.Point, RenderTextureFormat.ARGBHalf);
                
                m_TempPaddedDepthID = Shader.PropertyToID("_TempPaddedDepth");
                int tX = m_IsPadded ? Mathf.NextPowerOfTwo(cameraRTDesc.width) : cameraRTDesc.width;
                int tY = m_IsPadded ? Mathf.NextPowerOfTwo(cameraRTDesc.height) : cameraRTDesc.height;
                cameraRTDesc.width = tX;
                cameraRTDesc.height = tY;
                cmdBuffer.GetTemporaryRT(m_TempPaddedDepthID, cameraRTDesc, FilterMode.Trilinear);
            }
        
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                const int linearPass = 0;
                const int hiZPass = 1;
                const int compositePass = 2;
                
                CommandBuffer cmdBuffer = CommandBufferPool.Get("ArtSSR");
                cmdBuffer.Blit(m_ColorSource, m_TempPaddedDepthID, m_PaddedScale, Vector2.zero);
                
                // Calculate the reflection
                if (m_Settings.m_TracingMode == RayTracingMode.HiZTracing)
                {
                    cmdBuffer.Blit(null, m_ReflectionMapID, m_Settings.m_SSRMaterial, hiZPass);
                }
                else
                {
                    cmdBuffer.Blit(null, m_ReflectionMapID, m_Settings.m_SSRMaterial, linearPass);
                }
                
                // Composite the reflection
                cmdBuffer.Blit(m_TempPaddedDepthID, m_ColorSource, m_Settings.m_SSRMaterial, compositePass);
                
                cmdBuffer.ReleaseTemporaryRT(m_ReflectionMapID);
                cmdBuffer.ReleaseTemporaryRT(m_TempPaddedDepthID);
                
                context.ExecuteCommandBuffer(cmdBuffer);
                CommandBufferPool.Release(cmdBuffer);
            }

            public override void OnCameraCleanup(CommandBuffer cmdBuffer)
            {
                cmdBuffer.ReleaseTemporaryRT(m_ReflectionMapID);
                cmdBuffer.ReleaseTemporaryRT(m_TempPaddedDepthID);
                m_Frame++;
            }
        }
    }
    
}