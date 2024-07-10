using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ParticleSimTest
{
    class ParticleSimRenderPass : ScriptableRenderPass
    {
        // private List<ShaderTagId> m_ShaderTagIdList = new List<ShaderTagId>();
        private static readonly ShaderTagId m_MeshPassTag = new ShaderTagId("ParticleMeshPass");
        private FilteringSettings m_FilterSettings;

        public ParticleSimRenderPass(RenderQueueType renderQueueType, int layerMask)
        {
            RenderQueueRange renderQueueRange = (renderQueueType == RenderQueueType.Transparent)
                ? RenderQueueRange.transparent
                : RenderQueueRange.opaque;
            m_FilterSettings = new FilteringSettings(renderQueueRange, layerMask);
        }
        
        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmdBuffer = CommandBufferPool.Get();
            var shaderTagId = m_MeshPassTag;
            
            // ParticleSim particleSimObj = FindObjectByType<ParticleSim>();
            
            context.ExecuteCommandBuffer(cmdBuffer);
            cmdBuffer.Clear();

            var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
            var drawSettings = RenderingUtils.CreateDrawingSettings(shaderTagId, ref renderingData, sortFlags);
            
            context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref m_FilterSettings);
            
            CommandBufferPool.Release(cmdBuffer);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }
}