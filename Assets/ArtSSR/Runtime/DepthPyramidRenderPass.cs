using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ArtSSR
{
    public partial class ArtSSRRenderFeature
    {
        internal class ArtDepthPyramid : ScriptableRenderPass
        {
            public ArtSSREffect m_SSRVolume;

            private const string m_ProfilingTag = "ArtSSR_DepthPyramid";

            private readonly int m_NumThreads = 8;
            private const int m_NumSlices = 11;

            [SerializeField] internal ComputeShader m_DepthPyramidCS;

            private RTHandle m_DepthPyramidHandle;
            private ComputeBuffer m_DepthSliceResolutionBuffer = null;

            internal struct TargetSlice
            {
                internal int SliceIndex;
                internal Vector2Int PaddedResolution;
                internal Vector2Int ActualResolution;
                internal Vector2Int Scale;

                public static implicit operator int(TargetSlice slice) => slice.SliceIndex;
            }

            private TargetSlice[] m_Slices = new TargetSlice[m_NumSlices];
            private Vector2Int[] m_SliceResolutions = new Vector2Int[m_NumSlices];
            private Vector2 m_ScreenSize;
            private float m_Scale;

            public ArtDepthPyramid()
            {
                ReleaseSliceBuffer();
                CreateSliceBuffer();

                m_DepthPyramidCS = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/ArtSSR/Shaders/HiZCompute.compute");
            }

            public void Dispose()
            {
                ReleaseSliceBuffer();
            }

            void CreateSliceBuffer()
            {
                if (m_DepthSliceResolutionBuffer == null)
                {
                    m_DepthSliceResolutionBuffer = new ComputeBuffer(m_NumSlices, sizeof(int) * 2, ComputeBufferType.Default);
                }
            }

            void ReleaseSliceBuffer()
            {
                m_DepthSliceResolutionBuffer?.Release();
                m_DepthSliceResolutionBuffer = null;
            }

            void SetupComputeShader(CommandBuffer cmdBuffer, RTHandle depthPyramid, int srcSlice, int dstSlice, int srcW, int srcH, int dstW, int dstH)
            {
                int kernelDepthPyramid = m_DepthPyramidCS.FindKernel("CSMain");
                cmdBuffer.SetComputeTextureParam(m_DepthPyramidCS, kernelDepthPyramid, "_DepthPyramid", depthPyramid);
                cmdBuffer.SetComputeIntParam(m_DepthPyramidCS, "_SrcSlice", srcSlice);
                cmdBuffer.SetComputeIntParam(m_DepthPyramidCS, "_DstSlice", dstSlice);
                cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, "_SrcSize", new Vector2(srcW, srcH));
                cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, "_DstSize", new Vector2(dstW, dstH));
            }

            private void OnValidate() 
            {
                ReleaseSliceBuffer();
                CreateSliceBuffer();
            }

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraRTDesc)
            {

            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                m_Scale = m_SSRVolume.m_DownSample.value + 1.0f;

                int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width * m_Scale);
                int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height * m_Scale);

                int paddedWidth = Mathf.NextPowerOfTwo(width);
                int paddedHeight = Mathf.NextPowerOfTwo(height);

                m_ScreenSize.x = paddedWidth;
                m_ScreenSize.y = paddedHeight;

                for (int i = 0; i < m_NumSlices; i++)
                {
                    m_Slices[i].PaddedResolution.x = Mathf.Max(paddedWidth >> i, 1);
                    m_Slices[i].PaddedResolution.y = Mathf.Max(paddedHeight >> i, 1);

                    m_Slices[i].ActualResolution.x = Mathf.CeilToInt(width / (i + 1.0f));
                    m_Slices[i].ActualResolution.y = Mathf.CeilToInt(height / (i + 1.0f));
                    m_Slices[i].SliceIndex = i;

                    m_Slices[i].Scale.x = (int)(m_Slices[i].PaddedResolution.x / (float)paddedWidth);
                    m_Slices[i].Scale.y = (int)(m_Slices[i].PaddedResolution.y / (float)paddedHeight);

                    m_SliceResolutions[i] = m_Slices[i].PaddedResolution;
                }

                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.enableRandomWrite = true;
                desc.colorFormat = RenderTextureFormat.RFloat;
                desc.width = (int)m_ScreenSize.x;
                desc.height = (int)m_ScreenSize.y;
                desc.volumeDepth = m_NumSlices;
                desc.dimension = TextureDimension.Tex2DArray;

                RenderingUtils.ReAllocateIfNeeded(ref m_DepthPyramidHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_FinalDepthPyramid");
                m_DepthSliceResolutionBuffer.SetData(m_SliceResolutions);
                Shader.SetGlobalBuffer("_DepthPyramidResolutions", m_DepthSliceResolutionBuffer);
                cmd.SetGlobalTexture("_DepthPyramid", m_DepthPyramidHandle);

                ConfigureTarget(renderingData.cameraData.renderer.cameraColorTargetHandle, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                int kernelDepthPyramid = m_DepthPyramidCS.FindKernel("CSMain");
                int kernelDepthCopy = m_DepthPyramidCS.FindKernel("DepthCopy");

                float width = m_ScreenSize.x;
                float height = m_ScreenSize.y;

                float actualWidth = renderingData.cameraData.cameraTargetDescriptor.width;
                float actualHeight = renderingData.cameraData.cameraTargetDescriptor.height;

                {
                    var cmdBuffer = CommandBufferPool.Get(m_ProfilingTag + "_InitDepthPyramid");
                    cmdBuffer.SetComputeTextureParam(m_DepthPyramidCS, kernelDepthCopy, "_DepthPyramid", m_DepthPyramidHandle);
                    cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, "_SceneSize", new Vector2(actualWidth, actualHeight));
                    cmdBuffer.DispatchCompute(m_DepthPyramidCS, kernelDepthCopy, Mathf.CeilToInt(actualWidth / m_NumThreads), Mathf.CeilToInt(actualHeight / m_NumThreads), 1);
                    context.ExecuteCommandBuffer(cmdBuffer);
                    cmdBuffer.Clear();
                    CommandBufferPool.Release(cmdBuffer);
                }

                {
                    var cmdBuffer = CommandBufferPool.Get(m_ProfilingTag + "_CalcDepthPyramid");
                    cmdBuffer.SetExecutionFlags(CommandBufferExecutionFlags.AsyncCompute);
                    for (int i = 0; i < m_NumSlices - 1; i++)
                    {
                        SetupComputeShader(cmdBuffer, m_DepthPyramidHandle,
                            m_Slices[i], m_Slices[i + 1],
                            m_Slices[i].PaddedResolution.x, m_Slices[i].PaddedResolution.y,
                            m_Slices[i + 1].PaddedResolution.x, m_Slices[i + 1].PaddedResolution.y);

                        int groupX = Mathf.CeilToInt(m_Slices[i + 1].ActualResolution.x / m_NumThreads);
                        int groupY = Mathf.CeilToInt(m_Slices[i + 1].ActualResolution.y / m_NumThreads);

                        cmdBuffer.DispatchCompute(m_DepthPyramidCS, kernelDepthPyramid, groupX, groupY, 1);
                    }
                    context.ExecuteCommandBuffer(cmdBuffer);
                    cmdBuffer.Clear();
                    CommandBufferPool.Release(cmdBuffer);
                }
            }
        }
    }
}