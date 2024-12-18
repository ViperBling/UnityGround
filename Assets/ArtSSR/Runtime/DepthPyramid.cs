using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ArtSSR
{
    public class ArtDepthPyramid : ScriptableRendererFeature
    {
        private const int m_PyramidLevel = 11;

        [Serializable]
        internal struct Settings
        {
            [HideInInspector] internal ComputeShader PyramidShader;
            [SerializeField] internal bool ShowDebug;

            [Range(0, m_PyramidLevel - 1)] [SerializeField]
            internal int DebugSlice;

            [SerializeField] internal Vector2 DebugMinMax;
        }

        [SerializeField] internal ComputeShader m_DepthPyramidShader;
        [SerializeField] internal Settings m_Settings = new Settings();
        private DepthPyramidPass m_DepthPyramidPass = null;
        private ComputeBuffer m_DepthSliceBuffer = null;
        
        internal class DepthPyramidPass : ScriptableRenderPass
        {
            private readonly int m_NumThreads = 8;
            
            internal Settings m_Settings { get; }

            internal struct TargetSlice
            {
                internal int Slice;
                internal Vector2Int PaddedResolution;
                internal Vector2Int ActualResolution;
                internal Vector2Int Scale;

                // 重载
                public static implicit operator int(TargetSlice target)
                {
                    return target.Slice;
                }
            }

            private int m_FinalDepthPyramidID;
            private TargetSlice[] m_TmpSlices = new TargetSlice[m_PyramidLevel];
            private Vector2Int[] m_SliceResolutions = new Vector2Int[m_PyramidLevel];
            private ComputeBuffer m_DepthSliceResolutions = null;
            private Vector2 m_SceneSize;

            public DepthPyramidPass(ComputeBuffer depthSliceBuffer, Settings settings)
            {
                m_DepthSliceResolutions = depthSliceBuffer;
                m_Settings = settings;
            }

            void SetupComputeShader(CommandBuffer cmdBuffer, RenderTargetIdentifier depthPyramid, int srcSlice, int dstSlice, int srcW, int srcH, int dstW, int dstH)
            {
                cmdBuffer.SetComputeTextureParam(m_Settings.PyramidShader, 0, "_DepthPyramid", depthPyramid);
                cmdBuffer.SetComputeIntParam(m_Settings.PyramidShader, "_SrcSlice", srcSlice);
                cmdBuffer.SetComputeIntParam(m_Settings.PyramidShader, "_DstSlice", dstSlice);
                cmdBuffer.SetComputeVectorParam(m_Settings.PyramidShader, "_SrcSize", new Vector2(srcW, srcH));
                cmdBuffer.SetComputeVectorParam(m_Settings.PyramidShader, "_DstSize", new Vector2(dstW, dstH));
            }

            void SetupDebugComputeShader(CommandBuffer cmdBuffer, RenderTargetIdentifier depthPyramid, int curSlice, float low, float high)
            {
                cmdBuffer.SetComputeTextureParam(m_Settings.PyramidShader, 2, "_DepthPyramid", depthPyramid);
                cmdBuffer.SetComputeTextureParam(m_Settings.PyramidShader, 3, "_DepthPyramid", depthPyramid);
                cmdBuffer.SetComputeTextureParam(m_Settings.PyramidShader, 4, "_DepthPyramid", depthPyramid);
                cmdBuffer.SetComputeFloatParam(m_Settings.PyramidShader, "_Low", low);
                cmdBuffer.SetComputeFloatParam(m_Settings.PyramidShader, "_High", high);
                cmdBuffer.SetComputeIntParam(m_Settings.PyramidShader, "_DstSlice", curSlice);
            }

            public override void OnCameraSetup(CommandBuffer cmdBuffer, ref RenderingData renderingData)
            {
                int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width * GlobalArtSSRSettings.GlobalResolutionScale);
                int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height * GlobalArtSSRSettings.GlobalResolutionScale);

                // 最接近的完整的2次幂
                int paddedWidth = Mathf.NextPowerOfTwo(width);
                int paddedHeight = Mathf.NextPowerOfTwo(height);

                m_SceneSize.x = paddedWidth;
                m_SceneSize.y = paddedHeight;

                for (int i = 0; i < m_PyramidLevel; i++)
                {
                    // 计算每个深度层的分辨率
                    m_TmpSlices[i].PaddedResolution.x = Mathf.Max(paddedWidth >> i, 1);
                    m_TmpSlices[i].PaddedResolution.y = Mathf.Max(paddedHeight >> i, 1);

                    m_TmpSlices[i].ActualResolution.x = Mathf.CeilToInt(width / (i + 1.0f));
                    m_TmpSlices[i].ActualResolution.y = Mathf.CeilToInt(height / (i + 1.0f));

                    m_TmpSlices[i].Slice = i;

                    m_TmpSlices[i].Scale.x = (int)(m_TmpSlices[i].PaddedResolution.x / (float)paddedWidth);
                    m_TmpSlices[i].Scale.y = (int)(m_TmpSlices[i].PaddedResolution.y / (float)paddedHeight);

                    m_SliceResolutions[i] = m_TmpSlices[i].PaddedResolution;
                }
                m_FinalDepthPyramidID = Shader.PropertyToID("_FinalDepthPyramid");
                m_DepthSliceResolutions.SetData(m_SliceResolutions);
                Shader.SetGlobalBuffer("_DepthPyramidResolutions", m_DepthSliceResolutions);
                
                ConfigureTarget(renderingData.cameraData.renderer.cameraColorTargetHandle, renderingData.cameraData.renderer.cameraDepthTargetHandle);
            }
            
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                float width = m_SceneSize.x;
                float height = m_SceneSize.y;

                float actualWidth = renderingData.cameraData.cameraTargetDescriptor.width * GlobalArtSSRSettings.GlobalResolutionScale;
                float actualHeight = renderingData.cameraData.cameraTargetDescriptor.height * GlobalArtSSRSettings.GlobalResolutionScale;
                if (m_Settings.PyramidShader == null) return;
                
                // Init Depth Pyramid
                {
                    var cmdBuffer = CommandBufferPool.Get("InitDepthPyramid");
                    // 申请深度纹理数组
                    cmdBuffer.GetTemporaryRTArray(m_FinalDepthPyramidID, (int)width, (int)height, m_PyramidLevel, 0, FilterMode.Point, RenderTextureFormat.RFloat, RenderTextureReadWrite.Linear, 1, true);
                    cmdBuffer.SetComputeTextureParam(m_Settings.PyramidShader, 1, "_DepthPyramid", m_FinalDepthPyramidID);
                    cmdBuffer.SetComputeVectorParam(m_Settings.PyramidShader, "_SceneSize", new Vector2(actualWidth, actualHeight));
                    cmdBuffer.DispatchCompute(m_Settings.PyramidShader, 1, Mathf.CeilToInt(actualWidth / m_NumThreads), Mathf.CeilToInt(actualHeight / m_NumThreads), 1);
                    context.ExecuteCommandBuffer(cmdBuffer);
                    CommandBufferPool.Release(cmdBuffer);
                }
                
                // Calc Depth Pyramid
                {
                    var cmdBuffer = CommandBufferPool.Get("CalcDepthPyramid");
                    cmdBuffer.SetExecutionFlags(CommandBufferExecutionFlags.AsyncCompute);
                    for (int i = 0; i < m_PyramidLevel - 1; i++)
                    {
                        SetupComputeShader(cmdBuffer, m_FinalDepthPyramidID, 
                            m_TmpSlices[i], m_TmpSlices[i + 1],
                            m_TmpSlices[i].PaddedResolution.x, m_TmpSlices[i].PaddedResolution.y, 
                            m_TmpSlices[i + 1].PaddedResolution.x, m_TmpSlices[i + 1].PaddedResolution.y);

                        int groupX = Mathf.CeilToInt((float)m_TmpSlices[i + 1].ActualResolution.x / m_NumThreads);
                        int groupY = Mathf.CeilToInt((float)m_TmpSlices[i + 1].ActualResolution.y / m_NumThreads);
                        cmdBuffer.DispatchCompute(m_Settings.PyramidShader, 0, groupX, groupY, 1);
                    }
                    context.ExecuteCommandBufferAsync(cmdBuffer, ComputeQueueType.Background);
                    // context.ExecuteCommandBuffer(cmdBuffer);
                    CommandBufferPool.Release(cmdBuffer);
                }
                
#if UNITY_EDITOR
                // Debug Depth Pyramid
                if (m_Settings.ShowDebug)
                {
                    var cmdBuffer = CommandBufferPool.Get("DebugDepthPyramid");
                    int currentSlice = Mathf.Clamp(m_Settings.DebugSlice, 0, m_PyramidLevel - 1);
                    
                    SetupDebugComputeShader(cmdBuffer, m_FinalDepthPyramidID, currentSlice, m_Settings.DebugMinMax.x, m_Settings.DebugMinMax.y);

                    int groupX = Mathf.CeilToInt(width / m_NumThreads);
                    int groupY = Mathf.CeilToInt(height / m_NumThreads);
                    cmdBuffer.DispatchCompute(m_Settings.PyramidShader, 2, groupX, groupY, 1);
                    cmdBuffer.DispatchCompute(m_Settings.PyramidShader, 3, groupX, groupY, 1);
                    cmdBuffer.DispatchCompute(m_Settings.PyramidShader, 4, groupX, groupY, 1);

                    cmdBuffer.Blit(m_FinalDepthPyramidID, colorAttachmentHandle, Vector2.one, Vector2.zero, 0, 0);
                    
                    context.ExecuteCommandBuffer(cmdBuffer);
                    CommandBufferPool.Release(cmdBuffer);
                }
#endif
            }
            
            public override void OnCameraCleanup(CommandBuffer cmdBuffer)
            {
                base.OnCameraCleanup(cmdBuffer);
                cmdBuffer.ReleaseTemporaryRT(m_FinalDepthPyramidID);
            }
        }

        void ReleaseSliceBuffer()
        {
            if (m_DepthSliceBuffer != null)
            {
                m_DepthSliceBuffer.Release();
                m_DepthSliceBuffer = null;
            }
        }

        void CreateSliceBuffer()
        {
            if (m_DepthSliceBuffer == null)
            {
                m_DepthSliceBuffer = new ComputeBuffer(m_PyramidLevel, sizeof(int) * 2, ComputeBufferType.Default);
            }
        }

        private void OnDestroy()
        {
            ReleaseSliceBuffer();
        }

        private void OnDisable()
        {
            ReleaseSliceBuffer();
        }
        
        private void OnValidate()
        {
            ReleaseSliceBuffer();
            CreateSliceBuffer();
            Create();
        }
        
        public override void Create()
        {
            ReleaseSliceBuffer();
            CreateSliceBuffer();

            m_DepthPyramidPass = new DepthPyramidPass(m_DepthSliceBuffer, m_Settings);
            m_Settings.PyramidShader = m_DepthPyramidShader;
            m_DepthPyramidPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            if (m_Settings.ShowDebug)
            {
                m_DepthPyramidPass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (!renderingData.cameraData.postProcessEnabled) return;
            m_Settings.PyramidShader = m_DepthPyramidShader;
            if (!UniversalRenderPipelineDebugDisplaySettings.Instance.AreAnySettingsActive)
            {
                renderer.EnqueuePass(m_DepthPyramidPass);
            }
        }
    }
}