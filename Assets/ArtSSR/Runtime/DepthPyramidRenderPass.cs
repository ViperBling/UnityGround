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
            private const int m_NumSlices = 10 + 1;

            [SerializeField] internal ComputeShader m_DepthPyramidCS;

            private RTHandle m_DepthPyramidHandle;

            internal struct TargetSlice
            {
                internal int SliceIndex;
                internal Vector2 Resolution;
                internal Vector2 Scale;

                public static implicit operator int(TargetSlice slice) => slice.SliceIndex;
            }

            private TargetSlice[] m_Slices = new TargetSlice[m_NumSlices];
            private Vector2 m_ScreenSize;
            private float m_Scale;

            public ArtDepthPyramid()
            {
                m_DepthPyramidCS = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/ArtSSR/Shaders/HiZCompute.compute");
            }

            public void Dispose()
            {

            }

            void SetupComputeShader(CommandBuffer cmdBuffer, RTHandle depthPyramid, int srcSlice, int dstSlice, float srcW, float srcH, float dstW, float dstH)
            {
                int kernelDepthPyramid = m_DepthPyramidCS.FindKernel("CSMain");
                cmdBuffer.SetComputeTextureParam(m_DepthPyramidCS, kernelDepthPyramid, "_DepthPyramid", depthPyramid);
                cmdBuffer.SetComputeIntParam(m_DepthPyramidCS, "_SrcSlice", srcSlice);
                cmdBuffer.SetComputeIntParam(m_DepthPyramidCS, "_DstSlice", dstSlice);
                cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, "_SrcSize", new Vector2(srcW, srcH));
                cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, "_DstSize", new Vector2(dstW, dstH));
            }

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraRTDesc)
            {

            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                m_Scale = m_SSRVolume.m_DownSample.value + 1.0f;

                float width = renderingData.cameraData.cameraTargetDescriptor.width;
                float height = renderingData.cameraData.cameraTargetDescriptor.height;

                m_ScreenSize.x = width;
                m_ScreenSize.y = height;

                for (int i = 0; i < m_NumSlices; i++)
                {
                    float pow2 = Mathf.Pow(2, i);
                    m_Slices[i].Resolution.x = Mathf.Max(Mathf.Floor(width / pow2), 1);
                    m_Slices[i].Resolution.y = Mathf.Max(Mathf.Floor(height / pow2), 1);
                    m_Slices[i].SliceIndex = i;

                    m_Slices[i].Scale.x = (int)(m_Slices[i].Resolution.x / width);
                    m_Slices[i].Scale.y = (int)(m_Slices[i].Resolution.y / height);
                }

                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.enableRandomWrite = true;
                desc.sRGB = false;
                desc.colorFormat = RenderTextureFormat.RFloat;
                desc.width = (int)m_ScreenSize.x;
                desc.height = (int)m_ScreenSize.y;
                desc.volumeDepth = m_NumSlices;
                desc.dimension = TextureDimension.Tex2DArray;

                RenderingUtils.ReAllocateIfNeeded(ref m_DepthPyramidHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_FinalDepthPyramid");
                cmd.SetGlobalTexture("_DepthPyramid", m_DepthPyramidHandle);

                ConfigureTarget(renderingData.cameraData.renderer.cameraColorTargetHandle, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                int kernelDepthPyramid = m_DepthPyramidCS.FindKernel("CSMain");
                int kernelDepthCopy = m_DepthPyramidCS.FindKernel("DepthCopy");

                float width = m_ScreenSize.x;
                float height = m_ScreenSize.y;

                {
                    var cmdBuffer = CommandBufferPool.Get(m_ProfilingTag + "_InitDepthPyramid");
                    cmdBuffer.SetComputeTextureParam(m_DepthPyramidCS, kernelDepthCopy, "_DepthPyramid", m_DepthPyramidHandle);
                    cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, "_SceneSize", new Vector2(width, height));
                    cmdBuffer.DispatchCompute(m_DepthPyramidCS, kernelDepthCopy, Mathf.CeilToInt(width / m_NumThreads), Mathf.CeilToInt(height / m_NumThreads), 1);
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
                            m_Slices[i].Resolution.x, m_Slices[i].Resolution.y,
                            m_Slices[i + 1].Resolution.x, m_Slices[i + 1].Resolution.y);

                        int groupX = Mathf.CeilToInt(m_Slices[i + 1].Resolution.x / m_NumThreads);
                        int groupY = Mathf.CeilToInt(m_Slices[i + 1].Resolution.y / m_NumThreads);

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