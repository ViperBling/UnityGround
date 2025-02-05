using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Experimental.Rendering;

namespace SSR
{
    public partial class ScreenSpaceReflection
    {
        public class ScreenSpaceReflectionPass : ScriptableRenderPass
        {
            public SSRResolution m_RenderResolution;
            public SSRMipmapMode m_MipmapMode;

            public ScreenSpaceReflectionEffect m_SSRVolume;
            
            private readonly Material m_SSRMaterial;
            private RTHandle m_SourceHandle;
            private RTHandle m_ReflectHandle;
            
            private static readonly int m_MinSmoothnessID = Shader.PropertyToID("_MinSmoothness");
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
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                throw new System.NotImplementedException();
            }
        }
        
    }
}