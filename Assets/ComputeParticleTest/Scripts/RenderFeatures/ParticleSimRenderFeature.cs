using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering.Universal;

namespace ParticleSimTest
{
    public class ParticleSimRenderFeature : ScriptableRendererFeature
    {
        public RenderQueueType m_RenderQueueType;
        public LayerMask m_LayerMask;
        
        ParticleSimRenderPass m_ParticleSimRenderPass;

        public override void Create()
        {
            m_ParticleSimRenderPass = new ParticleSimRenderPass(m_RenderQueueType, m_LayerMask);

            // Configures where the render pass should be injected.
            m_ParticleSimRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        }

        // Here you can inject one or multiple render passes in the renderer.
        // This method is called when setting up the renderer once per-camera.
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(m_ParticleSimRenderPass);
        }
    }
}



