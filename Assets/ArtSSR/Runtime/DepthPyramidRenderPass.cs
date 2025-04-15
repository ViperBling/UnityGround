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
            public ArtScreenSpaceReflection m_SSRVolume;

            private const string m_ProfilingTag = "ArtSSR_DepthPyramid";

            private readonly int m_NumThreads = 8;
            private const int m_NumSlices = 11;

            [SerializeField] internal ComputeShader m_DepthPyramidCS;
            [SerializeField] internal Material m_DepthPyramidMaterial;

            private RTHandle m_DepthPyramidHandle;
            private RTHandle m_DepthPyramidPingHandle;
            private RTHandle m_DepthPyramidPongHandle;
            private RTHandle m_DepthPyramidCSHandle;

            private int[] m_DepthIDs;
            

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

            private static readonly int m_HiZPrevDepthLevelID = Shader.PropertyToID("_HiZPrevDepthLevel");
            private static readonly int m_SceneSizeID = Shader.PropertyToID("_SceneSize");

            public ArtDepthPyramid()
            {
                m_DepthPyramidCS = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/ArtSSR/Shaders/HiZCompute.compute");
                var depthShader = Shader.Find("Hidden/ArtSSR/HizCompute");
                m_DepthPyramidMaterial = CoreUtils.CreateEngineMaterial(depthShader);
            }

            public void Dispose()
            {
                m_DepthPyramidCSHandle?.Release();
                m_DepthPyramidHandle?.Release();
                m_DepthPyramidPingHandle?.Release();
                m_DepthPyramidPongHandle?.Release();
                CoreUtils.Destroy(m_DepthPyramidMaterial);
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

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                float width = renderingData.cameraData.cameraTargetDescriptor.width;
                float height = renderingData.cameraData.cameraTargetDescriptor.height;

                m_ScreenSize.x = width;
                m_ScreenSize.y = height;

                bool useComputeShader = m_SSRVolume.m_HiZUseCompute.value;
                if (useComputeShader)
                {
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

                    RenderingUtils.ReAllocateIfNeeded(ref m_DepthPyramidCSHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_DepthPyramidCS");
                    cmd.SetGlobalTexture(m_DepthPyramidCSHandle.name, m_DepthPyramidCSHandle);
                }
                else
                {
                    RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                    desc.depthBufferBits = 0;
                    desc.msaaSamples = 1;
                    desc.sRGB = false;
                    desc.enableRandomWrite = true;
                    desc.colorFormat = RenderTextureFormat.RFloat;
                    // desc.width = (int)m_ScreenSize.x;
                    // desc.height = (int)m_ScreenSize.y;
                    desc.useMipMap = true;
                    desc.mipCount = m_NumSlices;
                    desc.autoGenerateMips = false;
                    RenderingUtils.ReAllocateIfNeeded(ref m_DepthPyramidHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_DepthPyramid");

                    // desc.autoGenerateMips = false;
                    // RenderingUtils.ReAllocateIfNeeded(ref m_DepthPyramidPingHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_DepthPyramidPing");
                    // RenderingUtils.ReAllocateIfNeeded(ref m_DepthPyramidPongHandle, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_DepthPyramidPong");
                    cmd.SetGlobalTexture(m_DepthPyramidHandle.name, m_DepthPyramidHandle);
                }

                ConfigureInput(ScriptableRenderPassInput.Depth);
                ConfigureTarget(renderingData.cameraData.renderer.cameraColorTargetHandle, renderingData.cameraData.renderer.cameraDepthTargetHandle);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                float width = m_ScreenSize.x;
                float height = m_ScreenSize.y;

                bool useComputeShader = m_SSRVolume.m_HiZUseCompute.value;
                if (useComputeShader)
                {
                    int kernelDepthPyramid = m_DepthPyramidCS.FindKernel("CSMain");
                    int kernelDepthCopy = m_DepthPyramidCS.FindKernel("DepthCopy");

                    var cmdBuffer = CommandBufferPool.Get();
                    using (new ProfilingScope(cmdBuffer, new ProfilingSampler(m_ProfilingTag)))
                    {
                        cmdBuffer.SetComputeTextureParam(m_DepthPyramidCS, kernelDepthCopy, m_DepthPyramidCSHandle.name, m_DepthPyramidCSHandle);
                        cmdBuffer.SetComputeVectorParam(m_DepthPyramidCS, m_SceneSizeID, new Vector2(width, height));
                        cmdBuffer.DispatchCompute(m_DepthPyramidCS, kernelDepthCopy, Mathf.CeilToInt(width / m_NumThreads), Mathf.CeilToInt(height / m_NumThreads), 1);
                        context.ExecuteCommandBuffer(cmdBuffer);
                        cmdBuffer.Clear();
                        // CommandBufferPool.Release(cmdBuffer);

                        cmdBuffer.SetExecutionFlags(CommandBufferExecutionFlags.AsyncCompute);
                        for (int i = 0; i < m_NumSlices - 1; i++)
                        {
                            SetupComputeShader(cmdBuffer, m_DepthPyramidCSHandle,
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
                else
                {
                    int depthPyramid = m_DepthPyramidCS.FindKernel("GenerateDepthPyramid");

                    CommandBuffer cmdBuffer = CommandBufferPool.Get(m_ProfilingTag);
                    using (new ProfilingScope(cmdBuffer, new ProfilingSampler(m_ProfilingTag)))
                    {
                        Blitter.BlitCameraTexture(cmdBuffer, renderingData.cameraData.renderer.cameraDepthTargetHandle, m_DepthPyramidHandle, 0);

                        // Vector2Int 

                        // for (int i = 0;)
                        
                        // for (int i = 1; i < m_NumSlices; i++)
                        // {
                        //     cmdBuffer.SetGlobalInt(m_HiZPrevDepthLevelID, i - 1);
                        //     Blitter.BlitCameraTexture(cmdBuffer, m_DepthPyramidHandle, m_DepthPyramidPingHandle, m_DepthPyramidMaterial, 0);
                        //     // Blitter.BlitCameraTexture(cmdBuffer, m_DepthPyramidPingHandle, m_DepthPyramidPongHandle, i);
                        //     cmdBuffer.CopyTexture(m_DepthPyramidPingHandle, 0, i, m_DepthPyramidHandle, 0, i);
                        // }
                        // cmdBuffer.CopyTexture(m_DepthPyramidPongHandle, m_DepthPyramidHandle);

                        // context.ExecuteCommandBuffer(cmdBuffer);
                        // cmdBuffer.Clear();
                        // CommandBufferPool.Release(cmdBuffer);
                    }
                }
            }
        }
    }
}